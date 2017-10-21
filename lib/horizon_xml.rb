require 'mechanize'

class Hash
  def has_blank?
    self.values.any?{|v| v.nil? || v.length == 0}
  end
end

class Horizon_xml
  def initialize(debug = false)
    @debug        = debug
    @executed     = false
    @allow_blanks = false
    @period       = nil
    @info_url     = nil
    @comment_url  = nil
    @xml_url      = nil
    @domain       = nil
    @host_url     = 'http://myhorizon.solorient.com.au/Horizon/logonGuest.aw'
    @pagesize     = 1000
    @agent        = Mechanize.new
  end

  attr_accessor :allow_blanks
  attr_accessor :period
  attr_accessor :info_url
  attr_accessor :comment_url
  attr_accessor :xml_url
  attr_accessor :domain
  attr_accessor :host_url
  attr_accessor :pagesize

  def setPeriod(period = nil)
    case period
      when 'lastmonth'
        @period = "lastmonth"
        @xml_url = 'http://myhorizon.solorient.com.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+MONTH(Applications.Lodged-1)%3DSystemSettings.SearchMonthPrevious+AND+YEAR(Applications.Lodged)%3DSystemSettings.SearchYear+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedLastMonth&take=50&skip=0&start=0&pageSize=' + @pagesize.to_s
      when 'thismonth'
        @period = "thismonth"
        @xml_url = 'http://myhorizon.solorient.com.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+MONTH(Applications.Lodged)%3DCURRENT_MONTH+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedThisMonth&take=50&skip=0&start=0&pageSize=' + @pagesize.to_s
      else
        if (period.to_i >= 1960)
          @period = period.to_i.to_s
          @xml_url = ('http://myhorizon.solorient.com.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+Applications.AppYear%3D1960+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.Lodged+DESC%2CApplications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=Applications_List_Search&take=50&skip=0&start=0&pageSize=' + @pagesize.to_s).gsub('1960', period.to_i.to_s)
        else
          @period = "thisweek"
          @xml_url = 'http://myhorizon.solorient.com.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+WEEK(Applications.Lodged)%3DCURRENT_WEEK-1+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedThisWeek&take=50&skip=0&start=0&pageSize=' + @pagesize.to_s
        end
    end

    if @debug
      puts "Scraping for " + @period
    end

    self
  end

  def setCommentUrl(url = nil)
    @comment_url = url
    self
  end

  def setInfoUrl(url = nil)
    @info_url = url
    self
  end

  def setDomain(domain = nil)
    @domain = domain
    @host_url = @host_url + '?domain=' + @domain
    self
  end

  def setAgent(agent = Mechanize.new)
    @agent = agent
    self
  end

  def checkParams
    unless @period
      setPeriod('default')
    end

    raise "Info's URL is not set." unless @info_url
    raise "Comment's URL is not set." unless @comment_url
    raise "Host's URL is not set." unless @host_url
    raise "XML's URL is not set." unless @xml_url
    raise "Domain is not set." unless @domain

    true
  end

  def execute
    if checkParams
      @records = Array.new

      page = @agent.get(@host_url)
      page = @agent.get(@xml_url)

      xml = Nokogiri::XML(page.body)

      xml.xpath('//run_query_action_return/run_query_action_success/dataset/row').each do |app|
        record = {
            'council_reference' => app.xpath('AccountNumber').attribute('org_value').text.length > 0 ? app.xpath('AccountNumber').attribute('org_value').text.strip : nil,
            'address'           => app.xpath('Property').attribute('org_value').text.length > 0 ? (app.xpath('Property').attribute('org_value').text + ' NSW').strip : nil,
            'description'       => app.xpath('Description').attribute('org_value').text.length > 0 ? app.xpath('Description').attribute('org_value').text.strip : nil,
            'info_url'          => @info_url,
            'comment_url'       => @comment_url,
            'date_scraped'      => Date.today.to_s,
            'date_received'     => DateTime.parse(app.xpath('Lodged').attribute('org_value').text).to_date.to_s
        }

        if @debug
          p record
        end

        # adding record to records array
        if @allow_blanks
          @records << record
        else
          unless record.has_blank?
            @records << record
          end
        end

      end
    end
    self
  end

  def getRecords
    unless @executed
      execute
    end
    @records
  end
end

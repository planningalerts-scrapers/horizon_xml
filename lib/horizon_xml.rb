require 'mechanize'

class Hash
  def has_blank?
    self.values.any?{|v| v.nil? || v.length == 0}
  end
end

class Horizon_xml
  public def initialize(debug = false)
    @debug        = debug
    @executed     = false
    @allow_blanks = false
    @period       = nil
    @info_url     = nil
    @comment_url  = nil
    @xml_url      = nil
    @domain       = nil
    @cookie_url   = nil
    @base_url     = ''       # 'http://myhorizon.solorient.com.au/Horizon/' if it is cloud service
    @pagesize     = 500
    @start        = 0
    @agent        = nil
  end

  attr_accessor :allow_blanks
  attr_accessor :period
  attr_accessor :info_url
  attr_accessor :comment_url
  attr_accessor :domain
  attr_accessor :base_url
  attr_accessor :pagesize
  attr_accessor :agent

  private def _setPeriod(period = nil)
    case period
      when 'lastmonth'
        @period = "lastmonth"
        @xml_url = @base_url + 'urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+MONTH(Applications.Lodged-1)%3DSystemSettings.SearchMonthPrevious+AND+YEAR(Applications.Lodged)%3DSystemSettings.SearchYear+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedLastMonth&take=50&skip=0&start=' +@start.to_s+ '&pageSize=' + @pagesize.to_s
      when 'thismonth'
        @period = "thismonth"
        @xml_url = @base_url + 'urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+MONTH(Applications.Lodged)%3DCURRENT_MONTH+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedThisMonth&take=50&skip=0&start=' +@start.to_s+ '&pageSize=' + @pagesize.to_s
      else
        if (period.to_i >= 1960)
          @period = period.to_i.to_s
          @xml_url = (@base_url + 'urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+Applications.AppYear%3D1960+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.Lodged+DESC%2CApplications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=Applications_List_Search&take=50&skip=0&start=' +@start.to_s+ '&pageSize=' + @pagesize.to_s).gsub('1960', @period)
        else
          @period = "thisweek"
          @xml_url = @base_url + 'urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+WEEK(Applications.Lodged)%3DCURRENT_WEEK-1+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+Applications.CanDisclose%3D%27Yes%27+ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&query_name=SubmittedThisWeek&take=50&skip=0&start=' +@start.to_s+ '&pageSize=' + @pagesize.to_s
        end
    end
    self
  end

  private def _checkParams
    unless @agent
      @agent = Mechanize.new
    end

    _setPeriod(@period)
    @cookie_url = @base_url + 'logonGuest.aw?domain=' + @domain

    unless @info_url
      @info_url = @cookie_url
    end

    unless @comment_url
      @comment_url = @cookie_url
    end

    raise "Base's URL is not set." unless @base_url
    raise "Domain is not set." unless @domain

    true
  end

  private def _execute
    if _checkParams
      @records = Array.new

      if @debug
        puts "Scraping for " + @period
        puts "Base URL  : " + @base_url
        puts "Cookie URL: " + @cookie_url
        puts "XML URL   : " + @xml_url
      end

      page = @agent.get(@cookie_url)
      page = @agent.get(@xml_url)

      xml = Nokogiri::XML(page.body)

      total = xml.xpath('//run_query_action_return/run_query_action_success/dataset/total').text.to_i
      pages = total / @pagesize

      for i in 0..pages do
        if @debug
          puts 'checking page ' + (i+1).to_s + ' of ' + (pages+1).to_s
        end

        if i > 0
          @start = i * @pagesize
          setPeriod(@period)
          page = @agent.get(@xml_url)
          xml  = Nokogiri::XML(page.body)
        end

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
        end # do
      end # for
    end # if
    self
  end

  def getRecords
    unless @executed
      _execute
    end
    @records
  end
end

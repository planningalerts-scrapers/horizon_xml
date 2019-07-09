# frozen_string_literal: true

require "mechanize"
require "scraperwiki"

# Scrape horizon (solorient) site
class HorizonXml
  AUTHORITIES = {
    cowra: {},
    # Can't yet test liverpool_plains because it doesn't return any data for this month
    # liverpool_plains: {}
    uralla: {},
    walcha: {},
    weddin: {}
  }.freeze

  def self.scrape_and_save(authority)
    collector = HorizonXml.new
    collector.base_url = "http://myhorizon.solorient.com.au/Horizon/"

    if authority == :cowra
      collector.domain = "horizondap_cowra"
    elsif authority == :liverpool_plains
      collector.domain = "horizondap_lpsc"
    elsif authority == :uralla
      collector.domain = "horizondap_uralla"
    elsif authority == :walcha
      collector.domain = "horizondap_walcha"
    elsif authority == :weddin
      collector.domain = "horizondap"
    else
      raise "Unexpected authority: #{authority}"
    end

    collector.period = "thismonth"
    collector.records.each do |record|
      save(record)
    end
  end

  def self.save(record)
    puts "Saving record " + record["council_reference"] + ", " + record["address"]
    ScraperWiki.save_sqlite(["council_reference"], record)
  end

  def initialize
    # "http://myhorizon.solorient.com.au/Horizon/" if it is cloud service
    @base_url     = ""
    @pagesize     = 500
    @start        = 0
  end

  attr_accessor :period
  attr_accessor :domain
  attr_accessor :base_url

  def self.lastmonth_url(base_url, start, page_size)
    "#{base_url}urlRequest.aw?" \
               "actionType=run_query_action&" \
               "query_string=FIND+Applications+" \
               "WHERE+MONTH(Applications.Lodged-1)%3DSystemSettings.SearchMonthPrevious+AND+" \
               "YEAR(Applications.Lodged)%3DSystemSettings.SearchYear+AND+" \
               "Applications.CanDisclose%3D%27Yes%27+" \
               "ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&" \
               "query_name=SubmittedLastMonth&" \
               "take=50&" \
               "skip=0&" \
               "start=#{start}&" \
               "pageSize=#{page_size}"
  end

  def self.thismonth_url(base_url, start, page_size)
    query_string = "FIND+Applications+WHERE+" \
                   "MONTH(Applications.Lodged)%3DCURRENT_MONTH+AND+" \
                   "YEAR(Applications.Lodged)%3DCURRENT_YEAR+" \
                   "ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC"
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=#{query_string}&" \
      "query_name=SubmittedThisMonth&" \
      "take=50&" \
      "skip=0&" \
      "start=#{start}&" \
      "pageSize=#{page_size}"
  end

  def self.year_url(base_url, period, start, page_size)
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=FIND+Applications+" \
      "WHERE+" \
      "Applications.AppYear%3D#{period}+AND+" \
      "Applications.CanDisclose%3D%27Yes%27+" \
      "ORDER+BY+" \
      "Applications.Lodged+DESC%2C" \
      "Applications.AppYear+DESC%2C" \
      "Applications.AppNumber+DESC&" \
      "query_name=Applications_List_Search&" \
      "take=50&" \
      "skip=0&" \
      "start=#{start}&" \
      "pageSize=#{page_size}"
  end

  def self.thisweek_url(base_url, start, page_size)
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=FIND+Applications+" \
      "WHERE+" \
      "WEEK(Applications.Lodged)%3DCURRENT_WEEK-1+AND+" \
      "YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+" \
      "Applications.CanDisclose%3D%27Yes%27+" \
      "ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC&" \
      "query_name=SubmittedThisWeek&" \
      "take=50&" \
      "skip=0&" \
      "start=#{start}&" \
      "pageSize=#{page_size}"
  end

  def self.url(period, base_url, start, page_size)
    case period
    when "lastmonth"
      HorizonXml.lastmonth_url(base_url, start, page_size)
    when "thismonth"
      HorizonXml.thismonth_url(base_url, start, page_size)
    else
      if period.to_i >= 1960
        HorizonXml.year_url(base_url, period, start, page_size)
      else
        HorizonXml.thisweek_url(base_url, start, page_size)
      end
    end
  end

  def records
    agent = Mechanize.new

    @xml_url = HorizonXml.url(@period, @base_url, @start, @pagesize)

    @cookie_url = @base_url + "logonGuest.aw?domain=" + @domain

    @info_url ||= @cookie_url

    raise "Base's URL is not set." unless @base_url
    raise "Domain is not set." unless @domain

    @records = []

    agent.get(@cookie_url)
    page = agent.get(@xml_url)

    xml = Nokogiri::XML(page.body)

    total = xml.xpath("//run_query_action_return/run_query_action_success/dataset/total")
               .text
               .to_i
    pages = total / @pagesize

    (0..pages).each do |i|
      if i.positive?
        @start = i * @pagesize
        @xml_url = HorizonXml.url(@period, @base_url, @start, @pagesize)
        page = agent.get(@xml_url)
        xml  = Nokogiri::XML(page.body)
      end

      xml.xpath("//run_query_action_return/run_query_action_success/dataset/row").each do |app|
        council_reference = unless app.xpath("AccountNumber").attribute("org_value").text.empty?
                              app.xpath("AccountNumber").attribute("org_value").text.strip
                            end
        # TODO: Make state configurable
        address = unless app.xpath("Property").attribute("org_value").text.empty?
                    (app.xpath("Property").attribute("org_value").text + " NSW").strip
                  end

        description = unless app.xpath("Description").attribute("org_value").text.empty?
                        app.xpath("Description").attribute("org_value").text.strip
                      end

        record = {
          "council_reference" => council_reference,
          "address" => address,
          "description" => description,
          "info_url" => @info_url,
          "date_scraped" => Date.today.to_s,
          "date_received" => DateTime.parse(app.xpath("Lodged")
                             .attribute("org_value").text).to_date.to_s
        }

        # adding record to records array
        @records << record
      end
    end
    @records
  end
end

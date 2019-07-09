# frozen_string_literal: true

require "mechanize"
require "scraperwiki"

class Hash
  def has_blank?
    self.values.any?{|v| v.nil? || v.length == 0}
  end
end

# Scrape horizon (solorient) site
module HorizonXml
  AUTHORITIES = {
    cowra: {},
    # Can't yet test liverpool_plains because it doesn't return any data for this month
    # liverpool_plains: {}
    uralla: {},
    walcha: {},
    weddin: {},
    maitland: {}
  }.freeze

  def self.scrape_and_save(authority)
    if authority == :maitland
      scrape_and_save_maitland
    else
      base_url = "http://myhorizon.solorient.com.au/Horizon/"
      period = "thismonth"

      if authority == :cowra
        domain = "horizondap_cowra"
      elsif authority == :liverpool_plains
        domain = "horizondap_lpsc"
      elsif authority == :uralla
        domain = "horizondap_uralla"
      elsif authority == :walcha
        domain = "horizondap_walcha"
      elsif authority == :weddin
        domain = "horizondap"
      else
        raise "Unexpected authority: #{authority}"
      end

      HorizonXml.scrape_url(base_url, domain, period) do |record|
        save(record)
      end
    end
  end

  def self.save(record)
    puts "Saving record " + record["council_reference"] + ", " + record["address"]
    ScraperWiki.save_sqlite(["council_reference"], record)
  end

  def self.lastmonth_url(base_url, start, page_size)
    query_string = "FIND+Applications+" \
                   "WHERE+MONTH(Applications.Lodged-1)%3DSystemSettings.SearchMonthPrevious+AND+" \
                   "YEAR(Applications.Lodged)%3DSystemSettings.SearchYear+AND+" \
                   "Applications.CanDisclose%3D%27Yes%27+" \
                   "ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC"
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=#{query_string}&" \
      "query_name=SubmittedLastMonth&" \
      "take=50&" \
      "skip=0&" \
      "start=#{start}&" \
      "pageSize=#{page_size}"
  end

  def self.thismonth_url(base_url, start, page_size)
    query_string = "FIND Applications " \
                   "WHERE " \
                   "MONTH(Applications.Lodged)=CURRENT_MONTH AND " \
                   "YEAR(Applications.Lodged)=CURRENT_YEAR " \
                   "ORDER BY Applications.AppYear DESC,Applications.AppNumber DESC"
    query_string = query_string.gsub(" ", "+").gsub("=", "%3D").gsub(",", "%2C")
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
    query_string = "FIND+Applications+" \
                   "WHERE+" \
                   "Applications.AppYear%3D#{period}+AND+" \
                   "Applications.CanDisclose%3D%27Yes%27+" \
                   "ORDER+BY+" \
                   "Applications.Lodged+DESC%2C" \
                   "Applications.AppYear+DESC%2C" \
                   "Applications.AppNumber+DESC"
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=#{query_string}&" \
      "query_name=Applications_List_Search&" \
      "take=50&" \
      "skip=0&" \
      "start=#{start}&" \
      "pageSize=#{page_size}"
  end

  def self.thisweek_url(base_url, start, page_size)
    query_string = "FIND+Applications+" \
                   "WHERE+" \
                   "WEEK(Applications.Lodged)%3DCURRENT_WEEK-1+AND+" \
                   "YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+" \
                   "Applications.CanDisclose%3D%27Yes%27+" \
                   "ORDER+BY+Applications.AppYear+DESC%2CApplications.AppNumber+DESC"
    "#{base_url}urlRequest.aw?" \
      "actionType=run_query_action&" \
      "query_string=#{query_string}&" \
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

  def self.extract_total(page)
    xml = Nokogiri::XML(page.body)
    xml.xpath("//run_query_action_return/run_query_action_success/dataset/total").text.to_i
  end

  def self.scrape_page(page, cookie_url)
    xml = Nokogiri::XML(page.body)
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

      yield(
        "council_reference" => council_reference,
        "address" => address,
        "description" => description,
        "info_url" => cookie_url,
        "date_scraped" => Date.today.to_s,
        "date_received" => DateTime.parse(app.xpath("Lodged")
                           .attribute("org_value").text).to_date.to_s
      )
    end
  end

  def self.scrape_url(base_url, domain, period)
    page_size = 500
    cookie_url = "#{base_url}logonGuest.aw?domain=#{domain}"

    agent = Mechanize.new

    agent.get(cookie_url)
    page = agent.get(HorizonXml.url(period, base_url, 0, page_size))

    pages = extract_total(page) / page_size

    (0..pages).each do |i|
      page = agent.get(HorizonXml.url(period, base_url, i * page_size, page_size)) if i.positive?

      scrape_page(page, cookie_url) do |record|
        yield record
      end
    end
  end

  def self.scrape_and_save_maitland
    base_url  = "https://myhorizon.maitland.nsw.gov.au/Horizon/logonOp.aw?e=FxkUAB1eSSgbAR0MXx0aEBcRFgEzEQE6F10WSz4UEUMAZgQSBwVHHAQdXBNFETMAQkZFBEZAXxERQgcwERAAH0YWSzgRBFwdIxUHHRleNAMcEgA%3D#/home"
    thisweek  = "https://myhorizon.maitland.nsw.gov.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+Applications.ApplicationTypeID.IsAvailableOnline%3D%27Yes%27+AND+Applications.CanDisclose%3D%27Yes%27+AND+NOT(Applications.StatusName+IN+%27Pending%27%2C+%27Cancelled%27)+AND+WEEK(Applications.Lodged)%3DCURRENT_WEEK-1+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+Application.ApplicationTypeID.Classification%3D%27Application%27+ORDER+BY+Applications.Lodged+DESC&query_name=Application_LodgedThisWeek&take=100&skip=0&start=0&pageSize=100"
    thismonth = "https://myhorizon.maitland.nsw.gov.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+Applications.ApplicationTypeID.IsAvailableOnline%3D%27Yes%27+AND+Applications.CanDisclose%3D%27Yes%27+AND+NOT(Applications.StatusName+IN+%27Pending%27%2C+%27Cancelled%27)+AND+MONTH(Applications.Lodged)%3DCURRENT_MONTH+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+Application.ApplicationTypeID.Classification%3D%27Application%27+ORDER+BY+Applications.Lodged+DESC&query_name=Application_LodgedThisMonth&take=100&skip=0&start=0&pageSize=100"
    lastmonth = "https://myhorizon.maitland.nsw.gov.au/Horizon/urlRequest.aw?actionType=run_query_action&query_string=FIND+Applications+WHERE+Applications.ApplicationTypeID.IsAvailableOnline%3D%27Yes%27+AND+Applications.CanDisclose%3D%27Yes%27+AND+NOT(Applications.StatusName+IN+%27Pending%27%2C+%27Cancelled%27)+AND+MONTH(Applications.Lodged-1)%3DCURRENT_MONTH-1+AND+YEAR(Applications.Lodged)%3DCURRENT_YEAR+AND+Application.ApplicationTypeID.Classification%3D%27Application%27+ORDER+BY+Applications.Lodged+DESC&query_name=Application_LodgedLastMonth&take=100&skip=0&start=0&pageSize=100"

    comment_url = "mailto:info@maitland.nsw.gov.au"

    time = Time.new

    dateFrom = Date.new(time.year, time.month, 1).strftime('%d/%m/%Y')
    dateTo   = Date.new(time.year, time.month, -1).strftime('%d/%m/%Y')
    data_url = thismonth

    agent = Mechanize.new
    page = agent.get(base_url)
    page = agent.get(data_url)
    records = page.search("//row")

    records.each do |r|
      record = {}
      record["council_reference"] = r.at("EntryAccount")["org_value"] rescue nil
      record["address"]           = r.at("PropertyDescription")["org_value"].split(",")[0] rescue nil
      record["description"]       = r.at("Details")["org_value"] rescue nil
      record["info_url"]          = "https://myhorizon.maitland.nsw.gov.au/Horizon/embed.html"
      record["comment_url"]       = comment_url
      record["date_scraped"]      = Date.today.to_s
      record["date_received"]     = Date.strptime(r.at("Lodged")["org_value"], '%d/%m/%Y').to_s rescue nil

      unless record.has_blank?
        puts "Saving record " + record['council_reference'] + ", " + record['address']
    #       puts record
        ScraperWiki.save_sqlite(['council_reference'], record)
      end
    end
  end
end

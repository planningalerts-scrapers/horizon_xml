# frozen_string_literal: true

require "mechanize"
require "scraperwiki"
require "active_support/core_ext/hash"

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

      HorizonXml.scrape_url(
        "http://myhorizon.solorient.com.au/Horizon/",
        domain,
        "NSW"
      ) do |record|
        save(record)
      end
    end
  end

  def self.save(record)
    puts "Saving record " + record["council_reference"] + ", " + record["address"]
    ScraperWiki.save_sqlite(["council_reference"], record)
  end

  def self.thismonth_query
    "FIND Applications " \
    "WHERE " \
    "MONTH(Applications.Lodged)=CURRENT_MONTH AND " \
    "YEAR(Applications.Lodged)=CURRENT_YEAR " \
    "ORDER BY " \
    "Applications.Lodged DESC"
  end

  def self.thismonth_query2
    "FIND Applications " \
    "WHERE " \
    "Applications.ApplicationTypeID.IsAvailableOnline='Yes' AND " \
    "Applications.CanDisclose='Yes' AND " \
    "NOT(Applications.StatusName IN 'Pending', 'Cancelled') AND " \
    "MONTH(Applications.Lodged)=CURRENT_MONTH AND " \
    "YEAR(Applications.Lodged)=CURRENT_YEAR AND " \
    "Application.ApplicationTypeID.Classification='Application' " \
    "ORDER BY " \
    "Applications.Lodged DESC"
  end

  def self.query_url(base_url:, query_string:, query_name:, take:, start:, page_size:)
    "#{base_url}urlRequest.aw?" + {
      "actionType" => "run_query_action",
      "query_string" => query_string,
      "query_name" => query_name,
      "take" => take,
      "skip" => 0,
      "start" => start,
      "pageSize" => page_size
    }.to_query
  end

  def self.thismonth_url(base_url, start, page_size)
    query_url(
      base_url: base_url,
      query_string: thismonth_query,
      query_name: "SubmittedThisMonth",
      take: 50,
      start: start,
      page_size: page_size
    )
  end

  def self.thismonth_url2(base_url)
    query_url(
      base_url: base_url,
      query_string: thismonth_query2,
      query_name: "Application_LodgedThisMonth",
      take: 100,
      start: 0,
      page_size: 100
    )
  end

  def self.url(base_url, start, page_size)
    HorizonXml.thismonth_url(base_url, start, page_size)
  end

  def self.extract_total(page)
    xml = Nokogiri::XML(page.body)
    xml.xpath("//run_query_action_return/run_query_action_success/dataset/total").text.to_i
  end

  def self.extract_field(app, name)
    node = app.at(name)
    node["org_value"].strip if node
  end

  def self.scrape_page(page, info_url)
    xml = Nokogiri::XML(page.body)
    # We know about two different forms of this XML
    if xml.at("AccountNumber")
      council_reference_tag = "AccountNumber"
      address_tag = "Property"
      description_tag = "Description"
    else
      council_reference_tag = "EntryAccount"
      address_tag = "PropertyDescription"
      description_tag = "Details"
    end

    xml.search("row").each do |app|
      yield(
        "council_reference" => extract_field(app, council_reference_tag),
        "address" => extract_field(app, address_tag).split(", ")[0],
        "description" => extract_field(app, description_tag),
        "info_url" => info_url,
        "date_scraped" => Date.today.to_s,
        # TODO: Parse date based on knowledge of form
        "date_received" => DateTime.parse(extract_field(app, "Lodged")).to_date.to_s
      )
    end
  end

  def self.scrape_url(base_url, domain, state = nil)
    page_size = 500
    start_url = "#{base_url}logonGuest.aw?domain=#{domain}"

    agent = Mechanize.new

    agent.get(start_url)
    page = agent.get(HorizonXml.url(base_url, 0, page_size))

    pages = extract_total(page) / page_size

    (0..pages).each do |i|
      page = agent.get(HorizonXml.url(base_url, i * page_size, page_size)) if i.positive?

      scrape_page(page, start_url) do |record|
        record["address"] += " #{state}" if record["address"] && state

        yield record
      end
    end
  end

  def self.scrape_and_save_maitland
    base_url = "https://myhorizon.maitland.nsw.gov.au/Horizon/"
    start_url = "#{base_url}logonOp.aw?e=" \
                "FxkUAB1eSSgbAR0MXx0aEBcRFgEzEQE6F10WSz4UEUMAZgQSBwVHHAQdXBNFETMAQkZFBEZAXxER" \
                "QgcwERAAH0YWSzgRBFwdIxUHHRleNAMcEgA%3D#/home"
    info_url = "https://myhorizon.maitland.nsw.gov.au/Horizon/embed.html"

    agent = Mechanize.new
    agent.get(start_url)
    page = agent.get(thismonth_url2(base_url))

    scrape_page(page, info_url) do |record|
      save(record)
    end
  end
end

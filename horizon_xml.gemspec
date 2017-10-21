Gem::Specification.new do |s|
  s.name        = 'horizon_xml'
  s.version     = '1.0.5'
  s.date        = '2017-10-22'
  s.summary     = "Reformat SolOrient's Horizon XML feed"
  s.description = "My first gem that read SolOrient Horizon's published XML feed and convert it to a fixed set of records that could be consumed by other API like Planning Alerts's scraper."
  s.authors     = ["Eric Tam"]
  s.email       = 'eric.tam@traceyanderic.com'
  s.files       = ["lib/horizon_xml.rb"]
  s.homepage    = 'http://rubygems.org/gems/horizon_xml'
  s.license     = 'MIT'

  s.add_dependency "mechanize"
end

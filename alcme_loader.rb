require 'rubygems'
$KCODE = 'u'
require 'jcode'
require 'ferret'
require 'marc'
require 'lib/marc_document'
file = "/Volumes/External/shared/PermaFred/alcme_bulk.mrc"


config = YAML.load_file('config.yml')


index = Ferret::I.new(config['ferret']['config'])


collection = []

MARC::Reader.new(open(file)).each do |record|
  to_index = false
  old_doc = nil
  doc =  MARCDocument.new(record)
  doc[:source] = "errol.oclc.org"  

  index.search_each("lccn:#{doc[:lccn]}") do |id,score|
    old_doc = index[id]
  end
  if old_doc
    if(doc.compare_last_modified(old_doc) == :greater_than)
      to_index = true
    end
  else
    to_index = true
  end

  index << doc if to_index

end

index.optimize
puts index.size
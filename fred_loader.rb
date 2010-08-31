require 'rubygems'
$KCODE = 'u'
require 'jcode'
require 'stringio'
require 'bzip2'
require 'ferret'
require 'marc'
require 'lib/marc_document'
path = "/Users/rosssinger/tmp/2006-12-alpha/"
MARC::XMLReader.nokogiri!
#require 'rsolr'

#solr = RSolr.connect :url=>'http://anvil.lisforge.net:9292'

config = YAML.load_file('config.yml')

fi = Ferret::Index::FieldInfos.load(StringIO.new(config['ferret']['field_info'].to_yaml))
fi.create_index(config['ferret']['config'][:path])
index = Ferret::I.new(config['ferret']['config'])


def doc_to_doc(doc)
  doc.load
  new_doc = {}
  doc.each_pair do |key, val|
    key = case key
    when :alt_label then :alt_labels
    when :alt_label_str then :alt_labels_str
    when :last_modified then :marc_last_modified
    else key
    end
    new_doc[key] = val
  end
  new_doc[:source] = "Fred 2.0"
  new_doc[:last_modified] = DateTime.now
  new_doc
end

collection = []

Dir.open(path).each do | dir |
  next if dir == "." || dir == ".."
  Dir.open("#{path}#{dir}").each do | file |
    next if file == "." || file == ".."
    xml = ""
    fh = Bzip2::Reader.open("#{path}#{dir}/#{file}")
    while line = fh.gets
      xml << line
    end
    xml.sub!(/\<collection\>/, "<collection xmlns=\"http://www.loc.gov/MARC21/slim\">")
    marc = MARC::XMLReader.new(StringIO.new(xml))
    marc.each do | record |
      doc =  MARCDocument.new(record)
      doc[:source] = "Fred 2.0"
      index << doc
    end
  end
end

#solr.optimize
#puts index.size
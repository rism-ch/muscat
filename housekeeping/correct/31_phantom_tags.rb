require 'progress_bar'

pb = ProgressBar.new(Source.all.count)
@marc21 = Regexp.new('^[\=]([\d]{3,3})[\s]+(.*)$')

u = {}

config = MarcConfigCache.get_configuration "source"
all_tags = []
config.each_data_tag do |t|
  all_tags << t
end
all_tags << "001"

Source.all.each do |s|
  pb.increment!

  ## We need to parse it by hand

s.marc_source.each_line do |line| 
  if line.sub(/[\s\r\n]+$/, '') =~ @marc21
    tag = $1
    puts "#{s.id}: #{tag} #{$2}" if !all_tags.include?(tag)
  end
end

end
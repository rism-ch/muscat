pb = ProgressBar.new(Source.where("id > 400000000 and id < 420000000").count)

Source.where("id > 400000000 and id < 420000000").each do |se|
	s = Source.find(se.id) 
	#puts s.id
	pb.increment!
	s.marc.load_source(true)

	s.suppress_reindex
	s.suppress_update_77x
	s.suppress_update_count
	s.paper_trail_event = "CH Finalize Migration"
	s.save
	s = nil
end
	
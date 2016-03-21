# A Person is a physical person tied to one or more Sources.
# a person reference is generally stored also in the source's marc data
#
# === Fields
# * <tt>full_name</tt> - Full name of the person: Second name, Name
# * <tt>full_name_d</tt> - Downcase with UTF chars stripped 
# * <tt>life_dates</tt> - Dates in the form xxxx-xxxx
# * <tt>birth_place</tt>
# * <tt>gender</tt> - 0 = male, 1 = female
# * <tt>composer</tt> - 1 =  it is a composer
# * <tt>source</tt> - Source from where the bio info comes from
# * <tt>alternate_names</tt> - Alternate spelling of the name
# * <tt>alternate_dates</tt> - Alternate birth/death dates if uncertain 
# * <tt>comments</tt>
# * <tt>src_count</tt> - Incremented every time a Source tied to this person
# * <tt>hls_id</tt> - Used to match this person with the its biografy at HLS (http://www.hls-dhs-dss.ch/)
#
# Other wf_* fields are not shown

class Person < ActiveRecord::Base
  include ForeignLinks

  # class variables for storing the user name and the event from the controller
  @@last_user_save
  cattr_accessor :last_user_save
  @@last_event_save
  cattr_accessor :last_event_save
  
  has_paper_trail :on => [:update, :destroy], :only => [:marc_source], :if => Proc.new { |t| VersionChecker.save_version?(t) }
  
  def user_name
    user ? user.name : ''
  end
  
  resourcify 
  has_many :works
  has_and_belongs_to_many :sources
  has_and_belongs_to_many :institutions
  has_many :folder_items, :as => :item
  belongs_to :user, :foreign_key => "wf_owner"
  
  # People can link to themselves
  # This is the forward link
  has_and_belongs_to_many(:people,
    :class_name => "Person",
    :foreign_key => "person_a_id",
    :association_foreign_key => "person_b_id")
  
  # This is the backward link
  has_and_belongs_to_many(:referring_people,
    :class_name => "Person",
    :foreign_key => "person_b_id",
    :association_foreign_key => "person_a_id")
  
  composed_of :marc, :class_name => "MarcPerson", :mapping => [%w(marc_source to_marc)]
  
#  validates_presence_of :full_name  
  validate :field_length
  
  #include NewIds
  
  before_destroy :check_dependencies
  
  before_save :set_object_fields
  after_create :scaffold_marc, :fix_ids
  after_save :update_links, :reindex
  
  attr_accessor :suppress_reindex_trigger
  attr_accessor :suppress_scaffold_marc_trigger
  attr_accessor :suppress_recreate_trigger

  enum wf_stage: [ :inprogress, :published, :deleted ]
  enum wf_audit: [ :basic, :minimal, :full ]

  # Suppresses the marc scaffolding
  def suppress_scaffold_marc
    self.suppress_scaffold_marc_trigger = true
  end
  
  def suppress_recreate
    self.suppress_recreate_trigger = true
  end 
  
  # This is the last callback to set the ID to 001 marc
  # A Person can be created in various ways:
  # 1) using new() without an id
  # 2) from new marc data ("New Person" in editor)
  # 3) using new(:id) with an existing id (When importing Sources and when created as remote fields)
  # 4) using existing marc data with an id (When importing MARC data into People)
  # Items 1 and 3 will scaffold new Marc data, this means that the Id will be copied into 001 field
  # For this to work, the scaffolding needs to be done in after_create so we already have an ID
  # Item 2 is like the above, but without scaffolding. In after_create we copy the DB id into 001
  # Item 4 does the reverse: it copies the 001 id INTO the db id, this is done in before_save
  def fix_ids
    #generate_new_id
    # If there is no marc, do not add the id
    return if marc_source == nil

    # The ID should always be sync'ed if it was not generated by the DB
    # If it was scaffolded it is already here
    # If we imported a MARC record into Person, it is already here
    # THis is basically only for when we have a new item from the editor
    marc_source_id = marc.get_marc_source_id
    if !marc_source_id or marc_source_id == "__TEMP__"

      self.marc.set_id self.id
      self.marc_source = self.marc.to_marc
      self.without_versioning :save
    end
  end
  
  def update_links
    return if self.suppress_recreate_trigger == true

    allowed_relations = ["institutions", "people"]
    recreate_links(marc, allowed_relations)
  end
  
  # Do it in two steps
  # The second time it creates all the MARC necessary
  def scaffold_marc
    return if self.marc_source != nil  
    return if self.suppress_scaffold_marc_trigger == true
  
    new_marc = MarcPerson.new(File.read("#{Rails.root}/config/marc/#{RISM::MARC}/person/default.marc"))
    new_marc.load_source true
    
    new_100 = MarcNode.new("person", "100", "", "1#")
    new_100.add_at(MarcNode.new("person", "a", self.full_name, nil), 0)
    
    if self.life_dates
      new_100.add_at(MarcNode.new("person", "d", self.life_dates, nil), 1)
    end
    
    pi = new_marc.get_insert_position("100")
    new_marc.root.children.insert(pi, new_100)

    if self.id != nil
      new_marc.set_id self.id
    end
    
    if self.birth_place && !self.birth_place.empty?
      new_field = MarcNode.new("person", "370", "", "##")
      new_field.add_at(MarcNode.new("person", "a", self.birth_place, nil), 0)
      
      new_marc.root.children.insert(new_marc.get_insert_position("370"), new_field)
    end
    
    if self.gender && self.gender == 1 # only if female...
      new_field = MarcNode.new("person", "375", "", "##")
      new_field.add_at(MarcNode.new("person", "a", "female", nil), 0)

      new_marc.root.children.insert(new_marc.get_insert_position("375"), new_field)
    end
    
    if (self.alternate_names != nil and !self.alternate_names.empty?) || (self.alternate_dates != nil and !self.alternate_dates.empty?)
      new_field = MarcNode.new("person", "400", "", "1#")
      name = (self.alternate_names != nil and !self.alternate_names.empty?) ? self.alternate_names : self.full_name
      new_field.add_at(MarcNode.new("person", "a", name, nil), 0)
      new_field.add_at(MarcNode.new("person", "d", self.alternate_dates, nil), 1) if (self.alternate_dates != nil and !self.alternate_dates.empty?)
      
      new_marc.root.children.insert(new_marc.get_insert_position("400"), new_field)
    end

    if self.source != nil and !self.source.empty?
      new_field = MarcNode.new("person", "670", "", "##")
      new_field.add_at(MarcNode.new("person", "a", self.source, nil), 0)
    
      new_marc.root.children.insert(new_marc.get_insert_position("670"), new_field)
    end
    
    if self.comments != nil and !self.comments.empty?
      new_field = MarcNode.new("person", "680", "", "1#")
      new_field.add_at(MarcNode.new("person", "i", self.comments, nil), 0)
    
      new_marc.root.children.insert(new_marc.get_insert_position("680"), new_field)
    end    
    
    self.marc_source = new_marc.to_marc
    self.save!
  end
  
  # Suppresses the solr reindex
  def suppress_reindex
    self.suppress_reindex_trigger = true
  end
  
  def reindex
    return if self.suppress_reindex_trigger == true
    self.index
  end

  searchable :auto_index => false do |sunspot_dsl|
    sunspot_dsl.integer :id
    sunspot_dsl.string :full_name_order do
      full_name
    end
    sunspot_dsl.text :full_name
    sunspot_dsl.text :full_name_d
    
    sunspot_dsl.string :life_dates_order do
      life_dates
    end
    sunspot_dsl.text :life_dates
    
    sunspot_dsl.text :birth_place
    sunspot_dsl.text :source
    sunspot_dsl.text :alternate_names
    sunspot_dsl.text :alternate_dates
    
    sunspot_dsl.join(:folder_id, :target => FolderItem, :type => :integer, 
              :join => { :from => :item_id, :to => :id })
    
    sunspot_dsl.integer :src_count_order do 
      src_count
    end
    
    MarcIndex::attach_marc_index(sunspot_dsl, self.to_s.downcase)
    
  end
    
  # before_destroy, will delete Person only if it has no Source and no Work
  def check_dependencies
    if (self.sources.count > 0) || (self.works.count > 0)
      errors.add :base, "The person could not be deleted because it is used"
      return false
    end
  end
  
  def set_object_fields
    # This is called always after we tried to add MARC
    # if it was suppressed we do not update it as it
    # will be nil
    return if marc_source == nil
    
    # If the source id is present in the MARC field, set it into the
    # db record
    # if the record is NEW this has to be done after the record is created
    marc_source_id = marc.get_marc_source_id
    # If 001 is empty or new (__TEMP__) let the DB generate an id for us
    # this is done in create(), and we can read it from after_create callback
    self.id = marc_source_id if marc_source_id and marc_source_id != "__TEMP__"

    # std_title
    self.full_name, self.full_name_d, self.life_dates = marc.get_full_name_and_dates
    
    # alternate
    self.alternate_names, self.alternate_dates = marc.get_alternate_names_and_dates
    
    # varia
    self.gender, self.birth_place, self.source, self.comments = marc.get_gender_birth_place_source_and_comments
    
    self.marc_source = self.marc.to_marc
  end
  
  def field_length
    self.life_dates = self.life_dates.truncate(24) if self.life_dates and self.life_dates.length > 24
    self.full_name = self.full_name.truncate(128) if self.full_name and self.full_name.length > 128
  end
  
  def self.find_recent_updated(limit, user)
    if user != -1
      where("updated_at > ?", 5.days.ago).where("wf_owner = ?", user).limit(limit).order("updated_at DESC")
    else
      where("updated_at > ?", 5.days.ago).limit(limit).order("updated_at DESC") 
    end
  end
  
  def name
    return full_name
  end
  
  def autocomplete_label
    "#{full_name}" + (life_dates && !life_dates.empty? ? "  - #{life_dates}" : "")
  end

  ransacker :"100d_contains", proc{ |v| } do |parent| end
  ransacker :"375a_contains", proc{ |v| } do |parent| end
  ransacker :"374a_contains", proc{ |v| } do |parent| end
  ransacker :"100d_birthdate_contains", proc{ |v| } do |parent| end
  ransacker :"100d_deathdate_contains", proc{ |v| } do |parent| end
  ransacker :"043c_contains", proc{ |v| } do |parent| end
  ransacker :"551a_contains", proc{ |v| } do |parent| end

  def self.get_viaf(str)
    str.gsub!("\"", "")
    Viaf::Interface.search(str, self.to_s)
  end

end

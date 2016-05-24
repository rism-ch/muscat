# The Catalogue model describes a basic bibliograpfic catalog
# and is used to link Sources with its bibliographical info
#
# === Fields
# * <tt>name</tt> - Abbreviated name of the catalogue
# * <tt>author</tt> - Author
# * <tt>description</tt> - Full title
# * <tt>revue_title</tt> - if printed in a journal, the journal's title
# * <tt>volume</tt> - as above, the journal volume
# * <tt>place</tt>
# * <tt>date</tt>
# * <tt>pages</tt>
#
# === Relations
# * many to many with Sources

class Catalogue < ActiveRecord::Base
  include ForeignLinks
  include MarcIndex
  resourcify

  # class variables for storing the user name and the event from the controller
  @@last_user_save
  cattr_accessor :last_user_save
  @@last_event_save
  cattr_accessor :last_event_save
  
  has_paper_trail :on => [:update, :destroy], :only => [:marc_source], :if => Proc.new { |t| VersionChecker.save_version?(t) }

  has_and_belongs_to_many(:referring_sources, class_name: "Source", join_table: "sources_to_catalogues")
  has_and_belongs_to_many(:referring_institutions, class_name: "Institution", join_table: "institutions_to_catalogues")
  has_and_belongs_to_many :people, join_table: "catalogues_to_people"
  has_and_belongs_to_many :institutions, join_table: "catalogues_to_institutions"
  has_and_belongs_to_many :places, join_table: "catalogues_to_places"
  has_and_belongs_to_many :standard_terms, join_table: "catalogues_to_standard_terms"
  has_many :folder_items, :as => :item
  has_many :delayed_jobs, -> { where parent_type: "Catalogue" }, class_name: Delayed::Job, foreign_key: "parent_id"
  belongs_to :user, :foreign_key => "wf_owner"
  
  # This is the forward link
  has_and_belongs_to_many(:catalogues,
    :class_name => "Catalogue",
    :foreign_key => "catalogue_a_id",
    :association_foreign_key => "catalogue_b_id",
    join_table: "catalogues_to_catalogues")
  
  # This is the backward link
  has_and_belongs_to_many(:referring_catalogues,
    :class_name => "Catalogue",
    :foreign_key => "catalogue_b_id",
    :association_foreign_key => "catalogue_a_id",
    join_table: "catalogues_to_catalogues")
  
  
  composed_of :marc, :class_name => "MarcCatalogue", :mapping => %w(marc_source to_marc)
  
  ##include NewIds
  
  before_destroy :check_dependencies
  
  before_save :set_object_fields
  after_create :scaffold_marc, :fix_ids
  after_save :update_links, :reindex
  
  attr_accessor :suppress_reindex_trigger
  attr_accessor :suppress_scaffold_marc_trigger
  attr_accessor :suppress_recreate_trigger

  enum wf_stage: [ :inprogress, :published, :deleted ]
  enum wf_audit: [ :basic, :minimal, :full ]
  
  # Suppresses the solr reindex
  def suppress_reindex
    self.suppress_reindex_trigger = true
  end

  def suppress_scaffold_marc
    self.suppress_scaffold_marc_trigger = true
  end
  
  def suppress_recreate
    self.suppress_recreate_trigger = true
  end 
  
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

    allowed_relations = ["institutions", "people", "places", "catalogues", "standard_terms"]
    recreate_links(marc, allowed_relations)
  end
  
  def scaffold_marc
    return if self.marc_source != nil  
    return if self.suppress_scaffold_marc_trigger == true
 
    new_marc = MarcCatalogue.new(File.read("#{Rails.root}/config/marc/#{RISM::MARC}/catalogue/default.marc"))
    new_marc.load_source false
    
    #new_100 = MarcNode.new("catalogue", "100", "", "1#")
    #new_100.add_at(MarcNode.new("catalogue", "a", self.author, nil), 0)
    
    #new_marc.root.children.insert(new_marc.get_insert_position("100"), new_100)
    
    # save name
    node = MarcNode.new("catalogue", "210", "", "##")
    node.add_at(MarcNode.new("catalogue", "a", self.name, nil), 0)
    
    new_marc.root.children.insert(new_marc.get_insert_position("210"), node)

    # save decription
    node = MarcNode.new("catalogue", "240", "", "##")
    node.add_at(MarcNode.new("catalogue", "a", self.description, nil), 0)
    
    new_marc.root.children.insert(new_marc.get_insert_position("240"), node)

    # save date and place
    node = MarcNode.new("catalogue", "260", "", "##")
    node.add_at(MarcNode.new("catalogue", "c", self.date, nil), 0)
    node.add_at(MarcNode.new("catalogue", "a", self.place, nil), 0)

    new_marc.root.children.insert(new_marc.get_insert_position("260"), node)

    # save revue_title
    node = MarcNode.new("catalogue", "760", "", "0#")
    node.add_at(MarcNode.new("catalogue", "t", self.revue_title, nil), 0)
    
    new_marc.root.children.insert(new_marc.get_insert_position("760"), node)

    if self.id != nil
      new_marc.set_id self.id
    end

    self.marc_source = new_marc.to_marc
    self.save!
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
    self.place, self.date = marc.get_place_and_date
    self.name = marc.get_name
    self.description = marc.get_description
    self.author = marc.get_author
    self.revue_title = marc.get_revue_title
    self.marc_source = self.marc.to_marc
  end
  


  def reindex
    return if self.suppress_reindex_trigger == true
    self.index
  end

  searchable :auto_index => false do |sunspot_dsl|
    sunspot_dsl.integer :id
    sunspot_dsl.string :name_order do
      name
    end
    sunspot_dsl.text :name
    
    sunspot_dsl.string :author_order do
      author
    end
    sunspot_dsl.text :author
    
    sunspot_dsl.text :description
    sunspot_dsl.string :description_order do
      description
    end
 
    sunspot_dsl.text :revue_title
    sunspot_dsl.string :revue_title_order do
      revue_title
    end
 
    sunspot_dsl.text :volume
    sunspot_dsl.text :place
    sunspot_dsl.text :date
    sunspot_dsl.string :date_order do
      date
    end
 
    sunspot_dsl.text :pages
    
    sunspot_dsl.join(:folder_id, :target => FolderItem, :type => :integer, 
              :join => { :from => :item_id, :to => :id })
    
    sunspot_dsl.integer :src_count_order do 
      src_count
    end
    
    MarcIndex::attach_marc_index(sunspot_dsl, self.to_s.downcase)
    
  end
  
  def check_dependencies
    if (self.referring_sources.count > 0)
      errors.add :base, "The catalogue could not be deleted because it is used"
      return false
    end
  end
  
  def self.find_recent_updated(limit, user)
    if user != -1
      where("updated_at > ?", 5.days.ago).where("wf_owner = ?", user).limit(limit).order("updated_at DESC")
    else
      where("updated_at > ?", 5.days.ago).limit(limit).order("updated_at DESC") 
    end
  end

  def autocomplete_label
    
    aut = (author and !author.empty? ? author : nil)
    des = (description and !description.empty? ? description.truncate(45) : nil)
    dat = (date and !date.empty? ? date : nil)
    
    infos = [aut, dat, des].join(", ")
    
    "#{name}: #{infos}"
    
  end

  def get_items
    MarcSearch.select(Catalogue, '760$0', id.to_s).to_a
  end

  ransacker :"240g_contains", proc{ |v| } do |parent| end
  ransacker :"260b_contains", proc{ |v| } do |parent| end
  ransacker :"508a_contains", proc{ |v| } do |parent| end

end

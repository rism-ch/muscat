ActiveAdmin.register Person do

  menu :parent => "indexes_menu", :label => proc {I18n.t(:menu_people)}

  # Remove mass-delete action
  batch_action :destroy, false
  
  collection_action :autocomplete_person_full_name, :method => :get
  
  # See permitted parameters documentation:
  # https://github.com/gregbell/active_admin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # temporarily allow all parameters
  controller do
    
    autocomplete :person, :full_name, :display_value => :autocomplete_label , :extra_data => [:life_dates]
    
    after_destroy :check_model_errors
    before_create do |item|
      item.user = current_user
    end
    
    def check_model_errors(object)
      return unless object.errors.any?
      flash[:error] ||= []
      flash[:error].concat(object.errors.full_messages)
    end
    
    def permitted_params
      params.permit!
    end
    
    def edit
      @item = Person.find(params[:id])
      @editor_profile = EditorConfiguration.get_applicable_layout @item
      @page_title = "#{I18n.t(:edit)} #{@editor_profile.name} [#{@item.id}]"
    end
    
    def show
      @item = @person = Person.find(params[:id])
      @editor_profile = EditorConfiguration.get_show_layout @person
      @prev_item, @next_item, @prev_page, @next_page = Person.near_items_as_ransack(params, @person)
    end
    
    def index
      @results = Person.search_as_ransack(params)
      
      index! do |format|
        @people = @results
        format.html
      end
    end
    
    def new
      @person = Person.new
      
      new_marc = MarcPerson.new(File.read("#{Rails.root}/config/marc/#{RISM::BASE}/person/default.marc"))
      new_marc.load_source false # this will need to be fixed
      @person.marc = new_marc

      @editor_profile = EditorConfiguration.get_applicable_layout @person
      # Since we have only one default template, no need to change the title
      #@page_title = "#{I18n.t('active_admin.new_model', model: active_admin_config.resource_label)} - #{@editor_profile.name}"
      #To transmit correctly @item we need to have @source initialized
      @item = @person
    end

  end
  
  # Include the MARC extensions
  include MarcControllerActions
  
  # Include the folder actions
  include FolderControllerActions
  
  ###########
  ## Index ##
  ###########
  
  # temporary, to be replaced by Solr
  filter :full_name_equals, :label => proc {I18n.t(:any_field_contains)}, :as => :string
#  filter :name_contains, :as => :string
  
  # This filter passes the value to the with() function in seach
  # see config/initializers/ransack.rb
  # Use it to filter sources by folder
  filter :id_with_integer, :label => proc {I18n.t(:is_in_folder)}, as: :select, 
         collection: proc{Folder.where(folder_type: "Person").collect {|c| [c.name, "folder_id:#{c.id}"]}}
  
  index do
    selectable_column
    column (I18n.t :filter_id), :id  
    column (I18n.t :filter_full_name), :full_name
    column (I18n.t :filter_life_dates), :life_dates
    column (I18n.t :filter_sources), :src_count
    actions
  end
  
  ##########
  ## Show ##
  ##########
  
  show :title => proc{ active_admin_source_show_title( @item.full_name, @item.life_dates, @item.id) } do
    # @item retrived by from the controller is not available there. We need to get it from the @arbre_context
    active_admin_navigation_bar( self )
    @item = @arbre_context.assigns[:item]
    if @item.marc_source == nil
      render :partial => "marc_missing"
    else
      render :partial => "marc/show"
    end
    active_admin_embedded_source_list( self, person, params[:qe], params[:src_list_page] )
    active_admin_user_wf( self, person )
    active_admin_navigation_bar( self )
  end
  
  sidebar I18n.t(:search_sources), :only => :show do
    render("activeadmin/src_search") # Calls a partial
  end
  
  ##########
  ## Edit ##
  ##########
  
  sidebar :sections, :only => [:edit, :new] do
    render("editor/section_sidebar") # Calls a partial
    active_admin_submit_bar( self )
  end
  
  form :partial => "editor/edit_wide"

end

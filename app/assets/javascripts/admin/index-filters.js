// put this in e.g. app/assets/javascripts/admin/index-filters.coffee
// and include this in app/assets/javascripts/active_admin.js
 
var indexFiltersOnLoad = function() {
  // Modify the clear-filters button to clear saved filters by adding a parameter
  $('.clear_filters_btn').click(function()  {
    window.location.search = 'clear_filters=true'
  });

  // Do the same but for searching in embedded lists
  $('.embedded_search_btn').click(function() {
    window.location.search = 'clear_embedded_filters=true'
  });

};

$(indexFiltersOnLoad);
$(document).on("ready page:load", indexFiltersOnLoad);
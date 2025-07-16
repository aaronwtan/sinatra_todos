require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubi"

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

helpers do
  def list_complete?(list)
    todos_count(list).positive? && todos_remaining_count(list).zero?
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def todos_remaining_count(list)
    list[:todos].count { |todo| !todo[:completed] }
  end

  def todos_count(list)
    list[:todos].size
  end

  def todo_class(todo)
    "complete" if todo[:completed]
  end

  def sort_completed(array, view_block, &sort_criteria)
    complete, incomplete = array.partition(&sort_criteria)

    incomplete.each(&view_block)
    complete.each(&view_block)
  end

  def sort_lists(lists, &view_block)
    sort_completed(lists, view_block) { |list| list_complete?(list) }
  end

  def sort_todos(todos, &view_block)
    sort_completed(todos, view_block) { |todo| todo[:completed] }
  end
end

before do
  session[:lists] ||= []
end

get "/" do
  redirect "/lists"
end

# View list of lists
get "/lists" do
  @lists = session[:lists]
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Return an error message if the name is invalid. Return nil if the name is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "The list name must be between 1 and 100 characters."
  elsif session[:lists].any? { |list| list[:name] == name }
    "List name must be unique."
  end
end

# Return an error message if the todo name is invalid. Return nil if the name is valid.
def error_for_todo(name)
  "Todo must be between 1 and 100 characters." unless (1..100).cover? name.size
end

# Validate URL id and load corresponding list
def load_list(id)
  list = session[:lists].find { |list| list[:id] == id }

  return list if list

  session[:error] = "The specified list was not found."
  redirect "/lists"
end

# Generate unique identifier for element
def next_element_id(elements)
  max = elements.map { |element| element[:id] }.max || 0
  max + 1
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)

  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    id = next_element_id(session[:lists])
    session[:lists] << { id: id, name: list_name, todos: [] }
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# View a single list
get "/lists/:list_id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  erb :list, layout: :layout
end

# Render the edit list form
get "/lists/:list_id/edit" do
  list_id = params[:list_id].to_i
  @list = load_list(list_id)

  erb :edit_list, layout: :layout
end

# Update an existing todo list
post "/lists/:list_id" do
  list_id = params[:list_id].to_i
  @list = load_list(list_id)
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)

  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @list[:name] = list_name
    session[:success] = "The list has been updated."
    redirect "/lists/#{list_id}"
  end
end

# Delete a todo list
post "/lists/:list_id/destroy" do
  list_id = params[:list_id].to_i
  session[:lists].delete_if { |list| list[:id] == list_id }
  session[:success] = "The list has been deleted."

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    redirect "/lists"
  end
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  text = params[:todo].strip

  error = error_for_todo(text)

  if error
    session[:error] = error
    erb :list, layout: :layout
  else
    id = next_element_id(@list[:todos])
    @list[:todos] << { id: id, name: text, completed: false }
    session[:success] = "The todo was added."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:todo_id/destroy" do
  list_id = params[:list_id].to_i
  list = load_list(list_id)

  todo_id = params[:todo_id].to_i
  list[:todos].delete_if { |todo| todo[:id] == todo_id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    session[:success] = "The todo has been deleted."
    redirect "/lists/#{list_id}"
  end
end

# Update the status of a todo
post "/lists/:list_id/todos/:todo_id" do
  list_id = params[:list_id].to_i
  list = load_list(list_id)

  todo_id = params[:todo_id].to_i
  is_completed = params[:completed] == "true"
  todo = list[:todos].find { |todo| todo[:id] == todo_id }
  todo[:completed] = is_completed

  session[:success] = "The todo has been updated."
  redirect "/lists/#{list_id}"
end

# Mark all todos as complete for a list
post "/lists/:list_id/complete_all" do
  list_id = params[:list_id].to_i
  list = load_list(list_id)

  list[:todos].each { |todo| todo[:completed] = true }
  session[:success] = "All todos have been completed."
  redirect "/lists/#{list_id}"
end

not_found do
  erb :not_found, layout: :layout
end

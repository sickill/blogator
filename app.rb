require File.join(File.dirname(__FILE__), 'init.rb')
require 'sinatra/base'
require 'sinatras-hat'

class BlogApp < Sinatra::Base
  set :run, false
  set :app_file, __FILE__
  set :logging, true
  set :static, true
  set :root, APP_ROOT
  set :dump_errors, true

  eval File.read(File.join(APP_ROOT, 'environments', ENV['RACK_ENV'] || 'development') + '.rb')

  helpers do
    include Sickill::Helpers
  end

  not_found do
    erb :"404"
  end

  error do
    'Sorry there was a nasty error - ' + env['sinatra.error'].name
  end

  mount Post do
    finder { |model, params| model.all(:order => [:created_at.desc]) }
    record { |model, params| model.first(:id => params[:id]) }
    protect :all, :username => CONFIG_LOGIN, :password => CONFIG_PASSWORD, :realm => "BLOGZ"
  end

  before do
    @tags = Tag.all(:posts_count.gte => 1, :order => [:name])
    @archives = Post.published.to_a.group_by { |p| Date.new(p.published_at.year, p.published_at.month) }.map { |date, posts| posts.size }
  end

  get /^\/blog\/\d{4}\/\d{2}\/\d{2}\/([^\.]+)(\.\w+)?/ do
    @post = Post.published.first(:slug => params[:captures].first) or raise Sinatra::NotFound
    cache(:modified_at => @post.updated_at)
    @title = @post.title
    @keywords = @post.tag_list.split(", ")
    erb :"posts/show"
  end

  get /^\/(blog\/?)?$/ do
    @posts = Post.published
    cache(:modified_at => @posts.map { |p| p.updated_at }.max)
    erb :home
  end

  get '/blog/tag/:tag' do
    tag = Tag.first(:name => params[:tag])
    if tag
      @posts = tag.posts
      cache(:modified_at => @posts.map { |p| p.updated_at }.max)
      @title = "Posts tagged with '#{tag.name}':"
      @keywords = [tag.name]
      erb :"posts/list"
    else
      redirect "/"
    end
  end

  ['/blog/:year/?', '/blog/:year/:month/?'].each do |path|
    get path do
      year = params[:year].to_i
      params[:month] ? (start_month = end_month = params[:month].to_i) : (start_month, end_month = 1, 12)
      @posts = Post.published.all(:published_at => (DateTime.new(year, start_month)..DateTime.new(year, end_month, -1)))
      cache(:modified_at => @posts.map { |p| p.updated_at }.max)
      @title = "Archive for #{year}"
      @title << "/#{start_month.to_s.rjust(2, "0")}" if start_month == end_month
      @title << ":"
      erb :"posts/list"
    end
  end

  get '/:static_page' do
    page = params[:static_page]
    begin
      @content = render_static_page(File.read(APP_ROOT + "/content/" + page + ".txt"))
      @title = { "contact" => "Contact", "about-me" => "About Me", "projects" => "My projects" }[page]
      erb :static
    rescue Errno::ENOENT
      pass
    end
  end

  get '/projects/:project' do
    project = params[:project]
    begin
      @content = render_static_page(File.read(APP_ROOT + "/content/projects/" + project + ".txt"))
      @title = { "off" => "Open File Fast", "dece" => "DeCe", "rainbow" => "Rainbow" }[project]
      @keywords = [project]
      erb :static
    rescue Errno::ENOENT
      pass
    end
  end

  get '/atom/feed' do
    @posts = Post.published.all(:limit => 10)
    last_modified(@posts.first.try(:published_at)) # Conditinal GET, send 304 if not modified
    builder :atom
  end

end

BlogApp.run! if __FILE__ == $0

#
# (C) 2010 Paris Sinclair <paris@rubypanther.com>
# Need to decide on an OSS license for this. Maybe MIT?
interactive         = yes?("interactive? [y/N]")
root                = File.expand_path('.')
docroot             = File.join( root, 'public' )
static_location     = '/static'
vhost_address       = '*:80'
server_name         = "#{@app_name}.localdomain"
apache_conf_symlink = File.join '/etc/httpd/conf.d', "#{@app_name}.conf"
apache_conf         = File.join(root, 'config/apache/development.conf')

# run 'gem bundle'
gem_options = {}
begin
  add_source 'http://gems.github.com'
rescue
  gem_options = { :source => 'http://gems.github.com' }
end

unless interactive and not no?("Use Term::ANSIColor to colorize strings? (for use in logging) [Y/n]")
  gem 'term-ansicolor',       :require => 'term/ansicolor'

  initializer "monkey", <<-MONKEY
# So that we can use colors in the log easily
class String
  include Term::ANSIColor
end
MONKEY
end


gem 'mislav-will_paginate', { :require => 'will_paginate' }.merge(gem_options)
plugin 'exception_notifier',     :git => 'git://github.com/rails/exception_notification.git'
plugin 'restful-authentication', :git => 'git://github.com/technoweenie/restful-authentication.git'

@db_server = case interactive ? ask("Which database server? [P]ostgresql, [m]ysql, [s]qlite3") : 'postgresql'
             when /^m/i
               gem 'mysql'
               'mysql'
             when '^s'
               warn "sqlite3 database.yml may need configuration"
               gem 'sqlite3'
               'sqlite3'
             else
               gem 'pg', '0.8.0' rescue gem 'pg'
               'postgresql'
             end

@db_user     = ask("database username? [#{ENV['USER']}]") if interactive
@db_user     = ENV['USER'] if @db_user.to_s.empty?
@db_password = ask("database password? [none]") if interactive
# mysql often isn't configured to accept tcp connections
if %w/ mysql /.include? @db_server
  @db_socket   = `locate mysql.sock`.chomp
  @db_socket   = nil if @db_socket.empty?
end

run "rm public/index.html"
run "mv config/database.yml config/database-example.yml"

# TODO: add sqlite3 options
file 'config/database.yml', ERB.new(<<-ERB,nil,'<>').result(binding)
<% %w/ development production test /.each do |environment| %>
<%= environment %>:
  adapter: <%= @db_server %>
  encoding: utf8
  database: <%= @app_name %>_<%= environment %>
  username: <%= @db_user %>
  password: <%= @db_password %>
<% if @db_server == 'mysql' %>
  reconnect: false
  pool: 5
  host: localhost
<% end %>
<% if @db_socket %>
  socket: <%= @db_socket %>
<% else %>
  host: localhost
<% end %>
<% end %>
ERB

file 'app/views/layouts/application.html.erb', <<-LAYOUT
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<title>#{@app_name.capitalize rescue @app_name}</title>
<meta http-equiv="Content-type" content="text/html; charset=utf-8" />
<%= stylesheet_link_tag 'application' %>
</head>
<body>
<%= yield %>
</body>
</html>
LAYOUT

unless interactive and not no?("make apache Passenger config in config/apache.conf? [Y/n]")
  @apache = true
  run "mkdir config/apache"
  file apache_conf, <<-CONF
<VirtualHost #{vhost_address}>
  ServerName #{server_name}
  DocumentRoot #{docroot}
  ErrorLog #{root}/log/error_log
  CustomLog #{root}/log/access_log combined

  RackEnv development
  RailsEnv development

  <Directory #{docroot}>
    Order allow,deny
    Allow from all
  </Directory>

  <Location #{static_location}>
    PassengerEnabled off
  </Location>

</VirtualHost>
CONF
end

if @apache
  unless interactive and not no?("symlink config/apache.conf to #{apache_conf_symlink}? [Y/n]")
    run "sudo ln -s #{apache_conf} #{apache_conf_symlink}"
  end
end

run "bundle install"

git :init
git :add => ".", :commit => "-m 'initial commit.'"

unless no?( "run rake db:create:all to create databases? [Y/n]" )
  run "rake db:create:all"
end

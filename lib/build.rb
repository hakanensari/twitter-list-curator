require 'mechanize'
require 'twitter'
require 'yaml'

begin
  require 'launchy'
  require 'pry'

  class Mechanize::Page
    def show
      if body
        path = "/tmp/#{Time.now.to_i}.html"

        ::File.open(path, "w") do |f|
          f.write body
          f.close
        end

        Launchy.open "file://#{path}"
        system "sleep 2 && rm #{path} &"
      end
    end
  end
rescue LoadError
end

topics = YAML.load_file(File.expand_path('../../config/topics.yml', __FILE__))
twitter = YAML.load_file(File.expand_path('../../config/twitter.yml', __FILE__))

Twitter.configure { |c| twitter.each { |k, v| c.send("#{k}=", v) } }

agent = Mechanize.new { |a| a.user_agent_alias = 'Mac Safari' }

lists = Twitter.lists.first.last.map { |list| list["name"] }

topics.each do |topic|
  unless lists.include? topic
    Twitter.list_create topic, description: "#{topic}, scraped off Lanyrd"
  end

  handles = {}

  last = agent.get("http://lanyrd.com/topics/#{topic}/past/").
               at('.pagination li:last-child').text.to_i

  (1..last).each do |count|
    paths = agent.get("/topics/#{topic}/past/?page=#{count}").
                  search('.summary.url').
                  map { |node| node[:href] }

    paths.each do |path|
      agent.get(path) do |page|
        page.search('.people .handle').each do |node|
          handle = node.text.gsub(/@/, '')
          handles[handle] = handles[handle].to_i + 1
        end

        puts "#{topic} -> #{handles.count}"
      end
    end
  end

  handles.delete('guardian')

  (1..4).each do |count|
    selected = handles.select { |k, v| v >= count }
    selected.count < 200 ? break : handles = selected
  end

  handles.keys.each_slice(50) do |batch|
    begin
      Twitter.list_add_members('hakanensari', topic, batch)
    rescue Twitter::BadGateway, Twitter::InternalServerError
      retry
    end
  end
end

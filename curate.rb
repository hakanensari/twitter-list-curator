require 'bundler/setup'
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

        ::File.open(path, 'w') do |f|
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

copy    = 'Auto-curated by scraping Lanyrd'
topics  = YAML.load_file File.expand_path '../config/topics.yml',  __FILE__
twitter = YAML.load_file File.expand_path '../config/twitter.yml', __FILE__

Twitter.configure { |c| twitter.each { |k, v| c.send("#{k}=", v) } }

agent       = Mechanize.new { |a| a.user_agent_alias = 'Mac Safari' }
lists       = Twitter.lists.map { |list| list['name'] }

topics.each do |topic|
  begin
    if lists.include? topic
      Twitter.list_update topic, description: copy
    else
      Twitter.list_create topic, description: copy
    end
  rescue Twitter::Error
    retry
  end

  handles = {}

  last = agent
    .get("http://lanyrd.com/topics/#{topic}/past/")
    .at('.pagination li:last-child')
    .text
    .to_i

  (1..last).each_slice(10) do |batch|
    threads = batch.map do |count|
      Thread.new do
        agent
          .get("/topics/#{topic}/past/?page=#{count}")
          .search('.summary.url')
          .each do |node|
            agent.get(node[:href]) do |page|
              page
                .search('.people .handle')
                .each do |node|
                  handle          = node.text.gsub(/@/, '')
                  handles[handle] = handles[handle].to_i + 1
                end

              puts "#{topic} #{handles.count}"
            end
          end
      end
    end

    threads.each(&:join)
  end

  handles.delete 'guardian'

  (1..10).each do |count|
    selected = handles.select { |k, v| v >= count }
    selected.count < 25 ? break : handles = selected
  end

  begin
    current = Twitter
      .list_members(topic)
      .map(&:screen_name)
  rescue Twitter::Error
    retry
  end

  (handles.keys - current).each_slice(50) do |batch|
    begin
      Twitter.list_add_members topic, batch
    rescue Twitter::Error
      retry
    end
  end

  (current - handles.keys).each_slice(50) do |batch|
    begin
      Twitter.list_remove_members topic, batch
    rescue Twitter::Error
      retry
    end
  end

end

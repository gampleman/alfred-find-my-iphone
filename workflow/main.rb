#!/usr/bin/env ruby
# encoding: utf-8
require "./bundle/bundler/setup"
require "date"
require "yaml"
require "./xml_builder"
require "fileutils"
require "./locator"

class FindMyiPhone
  def initialize
    @creds_file = ".auth_token"
  end

  def store_creds(username, password)
    if username && username.length > 0 && password && password.length > 0
      File.open(@creds_file, 'w') do |f|
        f.write(username + "\n" + password)
      end
      file = Dir['./cache-*'].first
      FileUtils.rm file if file
    end
  end

  def load_creds
    File.read(@creds_file).each_line.to_a.map(&:strip)
  end

  def load_remote_devices(username, password)
    loc = IOSDeviceLocator.new username, password
    devices = loc.updateDevicesAndLocations
    File.open("./cache-#{DateTime.now}.yml", 'w') do |file|
      file.write(YAML.dump(devices))
    end
    devices
  end

  def list_devices(query)
    begin
      username, password = load_creds
    rescue Exception => e
      return XmlBuilder.build do |b|
        b.items do
          b.item Item.new(e.object_id, "authenticate", "No credentials found", "Run 'find authenticate &lt;username&gt; &lt;password&gt;' to set your iCloud creds", 'no')
        end
      end
    end
    begin
      devices = []
      file = Dir['./cache-*'].first
      if file
        match = file.match(/cache-(.+).yml/)
        d = DateTime.parse match[1]
        if (DateTime.now.to_time - d.to_time).to_i > 3600
          FileUtils.rm file
          devices = load_remote_devices(username, password)
        else
          devices = YAML.load_file file
        end
      else
        devices = load_remote_devices(username, password)
      end
      re = Regexp.new(query, 'i')
      devices.select! {|d| d['name'] =~ re || d['deviceDisplayName'] =~ re }
      XmlBuilder.build do |b|
        b.items do
          devices.each do |d|
            b.item Item.new(d['id'], d['id'], d['name'], d['deviceDisplayName'] + ' - Send alarm', 'yes', "icons/#{d['deviceStatus'].to_i == 200 ? 'online' : 'offline'}/#{d['rawDeviceModel']}.png")
          end
        end
      end
    rescue WrongCreds => e
      file = Dir['./cache-*'].first
      FileUtils.rm file if file
      return XmlBuilder.build do |b|
        b.items do
          b.item Item.new(e.object_id, "authenticate", "Unable to login to iCloud", "Run 'find authenticate &lt;username&gt; &lt;password&gt;' to set correct iCloud creds", 'no')
        end
      end
    end
  end

  def ring_device(query)
    username, password = load_creds
    loc = IOSDeviceLocator.new username, password
    loc.playSound query.strip, 'Hello from Alfred'
  end
end

obj = FindMyiPhone.new
if ARGV[0] == '--authenticate'
  obj.store_creds *ARGV[1].split(/\\\s+/)
  puts "Credentials saved"
elsif ARGV[0] == '--ring'
  obj.ring_device ARGV[1]
  puts "Alarm sent"
else
  puts obj.list_devices ARGV[0]
end

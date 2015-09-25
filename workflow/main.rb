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

  def show_login_ui!
    username = nil, password = nil
    result = `osascript -e 'tell application "SystemUIServer" to display dialog "In order to fetch your iOS devices, I need to configure your AppleID credentials. Please enter your AppleID email." default answer "Username" buttons ["Cancel", "Enter Password"] default button "Enter Password" cancel button "Cancel" with icon 2'`
    if result =~ /button returned:Enter Password, text returned:\s*(.+)\s*/
      username = $1
      result = `osascript -e 'tell application "SystemUIServer" to display dialog "In order to fetch your iOS devices, I need to configure your AppleID credentials. Please enter your AppleID password" default answer "Password" hidden answer true buttons ["Cancel", "Sign in"] default button "Sign in" cancel button "Cancel" with icon 2'`
      if result =~ /button returned:Sign in, text returned:(.+)\s*/
        password = $1
        store_creds username, password
        begin
          load_remote_devices username, password
          puts "You are now logged in. Go ahead and find your iPhone!"
        rescue WrongCreds => e
          puts "Looks like your username or password was wrong. Try again!"
        end
      end
    end
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

  def build_no_creds_response(message)
    XmlBuilder.build do |b|
      b.items do
        b.item Item.new(b.object_id, "authenticate", message, "Press ⏎ to enter your iCloud email and password.", 'yes')
      end
    end
  end

  def list_devices(query)
    begin
      username, password = load_creds
    rescue Exception => e
      return build_no_creds_response "No email and password found"
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
            description = [d['deviceDisplayName']]
            description << (d['batteryStatus'] == 'Unknown' ? nil : (d['batteryLevel'] * 100).round.to_s + '% Battery')
            description << 'Play Sound'
            b.item Item.new(d['id'], d['id'], d['name'], description.reject(&:nil?).join(' – '), 'yes', "icons/#{d['deviceStatus'].to_i == 200 ? 'online' : 'offline'}/#{d['rawDeviceModel']}.png")
          end
        end
      end
    rescue WrongCreds => e
      file = Dir['./cache-*'].first
      FileUtils.rm file if file
      return build_no_creds_response "Your email or password was invalid"
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
  q = ARGV[1]
  if q == 'authenticate'
    obj.show_login_ui!
    exit
  else
    obj.ring_device q
    puts "Alarm sent"
  end
else
  puts obj.list_devices ARGV[0]
end

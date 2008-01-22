#!/usr/bin/env ruby
#
# MozSnapshooter
# Web site thumbnailer
#
# Copyright (C) 2005 Mirko Maischberger
# Released in the Public Domain
#
# From an idea by Andrew McCall - <andrew@textux.com>
# http://www.hackdiary.com/archives/000055.html

require 'gtk2'
require 'gtkmozembed'
require 'imlib2'

class MozSnapshooter < Gtk::Window
  
  def initialize(location, target)
    super()
    self.title="MozSnapshooter"
    self.border_width = 1
    Gtk::MozEmbed.set_profile_path('/tmp/mozilla-profile-'+ENV['USER'].to_s, 'RubyGecko')
    self << Gtk::MozEmbed.new
    self.child.chrome_mask = Gtk::MozEmbed::ALLCHROME
    self.child.set_size_request(1024,1024)
    self.child.signal_connect("net_stop") { on_net_stop }
    self.child.location = location
    @target = target
    @countdown = 5

    # The user is bored, let's quit.
    self.signal_connect("destroy") do
      Gtk.main_quit
    end

    self.show_all
  end

  def on_net_stop
    Gtk::timeout_add(1000) do
      @countdown -= 1
      if(@countdown > 0)
        true
      else
        screenshot(@target)
        false
      end
    end
  end
  
  def screenshot(target=@target)
    gdkw = self.child.parent_window
    x, y, width, height, depth = gdkw.geometry
    width -= 16
    pixbuf = Gdk::Pixbuf.from_drawable(nil, gdkw, 0, 0, width, height)
    pixbuf.save(target,"png")
    img = Imlib2::Image.load(target)
    img.crop_scaled!(1, 1, 1024, 1024, 1024, 1024)
    img.save(target)
    img.delete!(true)
  ensure
    Gtk.main_quit
  end
  
end

ENV["LD_LIBRARY_PATH"] = "/usr/lib/firefox"

ms = MozSnapshooter.new ARGV[0], ARGV[1]
Thread.new{
  sleep(ARGV[0] =~ /^file:/ ? 60 : 180)
  ms.screenshot
  exit
}
Gtk.main

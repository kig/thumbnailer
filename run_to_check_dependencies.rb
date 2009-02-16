#!/usr/bin/env ruby

out = STDOUT.clone
STDOUT.reopen "/dev/null"
STDERR.reopen "/dev/null"

$missing = []

def check(name, args, deb_package, expected = 0)
  system("#{name} #{args}")
  $missing << [name, deb_package] if $?.exitstatus != expected 
end

check("convert", "-help", "imagemagick", 0)
check("dcraw", "-v", "dcraw", 1)
check("ffmpeg", "-h", "ffmpeg", 0)
check("firefox", "-h", "firefox", 0)
check("inkscape", "--help", "inkscape", 0)
check("test -n $(echo 'package require snack' | tclsh)", "", "libsnack2", 0)
check("mplayer", "-v", "mplayer", 0)
check("paps", "-?", "paps", 0)
check("pdftoppm", "-v", "poppler-utils", 99)
check("ps2pdf", "-h", "ghostscript", 1)
check("unoconv", "-h", "python-uno (and unoconv)", 1)
check("xvfb-run", "-h", "xvfb", 0)

check("ruby -rgtkmozembed", "-e nil", "libgtk-mozembed-ruby1.8") 
check("ruby -rimlib2", "-e nil", "libimlib2-ruby") 



$missing.each{|name, pkg| out.puts "Missing #{name} to be found in #{pkg}." }
out.puts "All dependencies found." if $missing.empty?

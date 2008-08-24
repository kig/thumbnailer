#   Thumbnailer - create thumbnails of files.
#   Copyright (C) 2007 Ilmari Heikkinen
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.


require 'metadata'


class Pathname

  def mkdir_p
    require 'fileutils'
    FileUtils.mkdir_p(to_s)
  end

  def glob(subpath, *args)
    self.class.glob((self+subpath).to_s, *args)
  end

end


module Thumbnailer
extend self

  attr_accessor :verbose, :quiet, :icon_dir, :keep_temp

  def thumbnail(filename, thumbnail_filename, size=nil, page=nil, crop='0x0+0+0', icon_fallback=true)
    nt = Metadata.no_text
    Metadata.no_text = true
    mt = filename.to_pn.mimetype
    mt.thumbnail(filename.to_s, thumbnail_filename, size, page, crop, icon_fallback)
    Metadata.no_text = nt
  end

end

Thumbnailer.icon_dir ||= __FILE__.to_pn.dirname + 'icons'


module Mimetype

  # Converts wanted page|layer|time of filename into an image,
  # scales the image to fit inside a thumbsize x thumbsize rectangle and
  # crops a WxH+X+Y rectangle out of the scaled image. Saves the image to
  # thumbnail.
  #
  #
  # Examples:
  #
  # Creating tiles from a PDF:
  #
  #   pdf = 'gsp0606.pdf'.to_pn
  #   tn_sz = pdf.dimensions.max
  #   pdf.pages.times do |page|
  #     (0 .. pdf.width / 256).each do |x|
  #       (0 .. pdf.height / 256).each do |y|
  #         pdf.thumbnail(pdf.to_s+"_#{page}_#{y}_#{x}.jpg", tn_sz, page,
  #                       "256x256+#{x*256}+#{y*256}")
  #       end
  #     end
  #   end
  #
  #
  # At specific size:
  #
  #   pdf = 'gsp0606.pdf'.to_pn
  #   tn_sz = 2048
  #   pdf.pages.times do |page|
  #     4.times do |x|
  #       4.times do |y|
  #         pdf.thumbnail(pdf.to_s+"_#{page}_#{y}_#{x}.jpg", tn_sz, page,
  #                       "512x512+#{x*512}+#{y*512}")
  #       end
  #     end
  #   end
  #
  #
  # Or just:
  #
  #   pdf = 'gsp0606.pdf'.to_pn
  #   pdf.create_tiles    # (256, 1024, [3,4]){|pg,x,y| "#{pg}_#{y}_#{x}.png" }
  #
  def thumbnail(filename, thumb_filename,
                thumb_size=nil, page=nil, crop='0x0+0+0', icon_fallback=true)
    # puts "called thumbnail for #{filename} (#{to_s})"
    begin
      if to_s =~ /video|matroska|realmedia/
        fancy_video_thumbnail(filename, thumb_filename, thumb_size, page)
        # page ||= [[5.7, filename.to_pn.length * 0.5].max,
        #            filename.to_pn.length * 0.75].min
        # ffmpeg_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /html/
        page ||= 0
        html_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /pdf/
        page ||= 0
        pdf_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif is_a?(Mimetype['image/x-dcraw'])
        page = 0
        dcraw_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /image/
        page ||= 0
        image_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /[-\/]dvi$/
        page ||= 0
        dvi_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /postscript/
        page ||= 0
        postscript_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /^text/
        page ||= 0
        text_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /powerpoint|vnd\.oasis\.opendocument|msword|ms-excel|rtf|x-tex|template|stardivision|comma-separated-values|dbf|vnd\.sun\.xml/
        page ||= 0
        unoconv_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /^audio/
        page ||= 0
        waveform_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      end
    rescue Exception => e
      unless Thumbnailer.quiet
        STDERR.puts "Failed to thumbnail #{filename}#{", falling back to icon" if icon_fallback}"
        if Thumbnailer.verbose
          STDERR.puts e, e.message, e.backtrace
        end
      end
      false
    end or (icon_fallback && icon_thumbnail(filename, thumb_filename, thumb_size, crop))
  rescue Exception => e
    unless Thumbnailer.quiet
      if icon_fallback
        STDERR.puts "Failed to thumbnail and iconize #{filename}"
      end
      if Thumbnailer.verbose
        STDERR.puts e, e.message, e.backtrace
      end
    end
    false
  end

  def icon_thumbnail(filename, thumb_filename, thumb_size, crop='0x0+0+0')
    ic = icon
    mt = (ic.extname == '.png' ? Mimetype['image/png'] : Mimetype['image/svg+xml'])
    mt.image_thumbnail(ic, thumb_filename, thumb_size, 0, crop)
  end

  def icon
    ic = ancestors.map do |klass|
      pn = Thumbnailer.icon_dir + (klass.to_s.downcase.gsub(/\//, '-')+".svg")
      unless pn.exist?
        pn = Thumbnailer.icon_dir + (klass.to_s.downcase.gsub(/\//, '-')+".png")
      end
      pn
    end.find{|pn| pn.exist? }
    unless ic
      ic = Thumbnailer.icon_dir + "default.svg"
      unless ic.exist?
        ic = Thumbnailer.icon_dir + "default.png"
      end
    end
    ic
  end

  def image_thumbnail(filename, thumb_filename, thumb_size, page=0, crop='0x0+0+0')
    if to_s == 'image/x-xcf'
      return false
    end
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname + "tmp-#{Process.pid}-#{Thread.current.object_id}#{tfn.extname}"
    if to_s =~ /^image/ and not to_s =~ /svg/
      begin
        require 'imlib2'
        img = Imlib2::Image.load(filename.to_s)
        begin
          ow, oh = img.width, img.height
          larger = [ow, oh].max
          wr = img.width.to_f / larger
          hr = img.height.to_f / larger
          thumb_size ||= larger
          sr = larger / thumb_size.to_f
          w,h,x,y = crop.scan(/[+-]?[0-9]+/).map{|i|i.to_i}
          w = thumb_size * wr if w == 0
          h = thumb_size * hr if h == 0
          rx,ry,rw,rh = [x,y,w,h].map{|i| i * sr }
          ctx = Imlib2::Context.get
          ctx.blend = false
          ctx.color = Imlib2::Color::TRANSPARENT
          ctx.op = Imlib2::Op::COPY
          if rx > ow or ry > oh
            nimg = Imlib2::Image.new(w, h)
            nimg.has_alpha = true
            nimg.fill_rectangle([0, 0, w, h])
          else
            nimg = img.crop_scaled(rx,ry,rw,rh, w, h)
            nimg.has_alpha = true
            if rx+rw > ow
              d = rx+rw - ow
              nimg.fill_rectangle([w - d / sr, 0, w, h])
            elsif ry+rh > oh
              d = ry+rh - oh
              nimg.fill_rectangle([0, h - d / sr, w, h])
            end
          end
          ctx.blend = true
          nimg.save(tmp_filename.to_s)
        ensure
          img.delete!
          nimg.delete!(true) if nimg
        end
      rescue Exception
        # failed to load image
      end
    end
    if tmp_filename.exist?
      tmp_filename.rename(tfn)
      return true
    end
    original_filename = filename
    ex = filename.to_pn.extname
    unless extnames.include?(ex)
      ex = extname
      ex = '.svg' if ex == '.svgz'
      ex = '.tga' if ex == '.icb'
    end
    filename = tfn.dirname + "tmp-#{Process.pid}-#{Thread.current.object_id}-src#{ex}"
    begin
      require 'fileutils'
      FileUtils.ln_s(File.expand_path(original_filename.to_s), File.expand_path(filename.to_s))
      filename.mimetype = self
      dims = filename.dimensions
      return false unless dims[0] and dims[1]
      larger = dims.max
      thumb_size ||= 2048
      case filename.metadata['Image.DimensionUnit']
      when 'mm'
        scale_fac = larger.mm_to_points / 72.0
      else
        scale_fac = larger / 72.0
      end
      density = thumb_size / scale_fac
      secure_filename(filename){|sfn, uqsfn|
        if to_s =~ /svg/
          args = [
                  uqsfn,
                  "-w", ((dims[0] / larger.to_f) * thumb_size).to_i.to_s,
                  "-h", ((dims[1] / larger.to_f) * thumb_size).to_i.to_s,
                  "--export-png", tmp_filename.to_s + ".png",
                  ]
          system("xvfb-run", "-a", "-s", "-screen 0 514x514x24", "inkscape", *args)
          if File.exist?(tmp_filename.to_s+".png")
            Mimetype['image/png'].image_thumbnail(tmp_filename.to_s+".png", tmp_filename.to_s, thumb_size, page, crop)
            File.unlink(tmp_filename.to_s+".png")
          end
        else
          args = ["-density", density.to_s,
                  "#{uqsfn}[#{page}]",
                  "-scale", "#{thumb_size}x#{thumb_size}"]
          if crop and crop.to_s != '0x0+0+0'
            args << "-crop" << crop.to_s
          end
          args << tmp_filename.to_s
          system("convert", *args)
        end
      }
    ensure
      filename.unlink if filename.exist?
    end
    if tmp_filename.exist?
      tmp_filename.rename(tfn)
      true
    else
      false
    end
  end

  PNMPROGS = {
    ".jpg" => "pnmtojpeg",
    ".png" => "pnmtopng"
  }

  def waveform_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    if to_s == "audio/x-ape"
      return false
    end
    tfn = thumb_filename.to_pn.expand_path
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-waveform.png"
    tmp2_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-waveform2.png"
    secure_filename(filename){|sfn, uqsfn|
      if ['audio/x-wav', 'audio/mpeg'].include?(to_s)
        system('xvfb-run', '-a', '-s', "-screen 0 514x514x24", "audiothumb", uqsfn, tmp_filename.to_s)
      else
        tmp2 = tmp_filename.to_s + ".wav"
        system("mplayer", "-vc", "null", "-vo", "null",
                "-ao", "pcm:fast:file=#{tmp2}", uqsfn)
        system('xvfb-run', '-a', '-s', "-screen 0 514x514x24", "audiothumb", tmp2, tmp_filename.to_s)
        File.unlink(tmp2) if File.exist?(tmp2)
      end
    }
    rv = false
    if tmp_filename.exist?
      w,h = tmp_filename.dimensions
      system("convert", tmp_filename.to_s, "-crop", "#{w-2}x#{h-2}+1+1", tmp2_filename.to_s)
      rv = Mimetype['image/png'].image_thumbnail(tmp2_filename, thumb_filename,
                                                 thumb_size, page, crop)
      tmp_filename.unlink
      tmp2_filename.unlink
    end
    rv
  end

  def cond_mv(src, dst)
    FileUtils.mv(src, dst) if File.exist?(src) and
      File.expand_path(src.to_s) != File.expand_path(dst.to_s) and
      File.size(src) > 0
  end

  def text_to_pdf(filename, pdf_filename)
    charset = filename.to_pn.metadata['Doc.Charset']
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(pdf_filename) {|tsfn, uqtsfn|
        system("iconv -f #{charset} -t utf8 #{sfn} | " +
               "paps --font='Monospace 11' --columns 1 | ps2pdf - #{tsfn}")
        cond_mv(uqtsfn, pdf_filename)
      }
    }
  end

  COMPRESSION_FILTERS = {'.gz' => 'zcat', '.bz2' => 'bzcat'}
  def postscript_to_pdf(filename, pdf_filename)
    filter = COMPRESSION_FILTERS[File.extname(filename.to_s)] || "cat"
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(pdf_filename){|tsfn, uqtsfn|
        system("#{filter} #{sfn} | ps2pdf - #{tsfn}")
        cond_mv(uqtsfn, pdf_filename)
      }
    }
  end

  def dvi_to_pdf(filename, pdf_filename)
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(pdf_filename){|tsfn, uqtsfn|
        system("dvipdfm -o #{tsfn} #{sfn}")
        cond_mv(uqtsfn, pdf_filename)
      }
    }
  end

  def unoconv_to_pdf(filename, pdf_filename)
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(pdf_filename){|tsfn, uqtsfn|
        system("xvfb-run -a unoconv -f pdf --stdout #{sfn} > #{tsfn}")
        if File.exist?(uqtsfn) and File.size(uqtsfn) < 4096
          if File.read(uqtsfn).strip =~ /The provided document cannot be converted to the desired format.\Z/
            File.unlink(uqtsfn)
          end
        end
        cond_mv(uqtsfn, pdf_filename)
      }
    }
  end

  def pdf_convert_thumbnail(method, filename, thumb_filename, thumb_size, page, crop)
    tfn = filename.to_pn
    tmp_filename = tfn.dirname + "#{File.basename(filename)}-temp.pdf"
    __send__(method, filename, tmp_filename) unless tmp_filename.exist?
    rv = false
    if tmp_filename.exist?
      rv = pdf_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink if (!rv or !Thumbnailer.keep_temp)
    end
    rv
  end

  %w(text postscript dvi unoconv).each{|m|
    module_eval <<-EOF
      def #{m}_thumbnail(*a)
        pdf_convert_thumbnail(#{"#{m}_to_pdf".dump}, *a)
      end
    EOF
  }

  def pdf_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    w,h,x,y = crop.scan(/[+-]?[0-9]+/).map{|i|i.to_i}
    secure_filename(filename){|sfn, uqsfn|
      args = ["-x", x,
              "-y", y,
              "-W", w,
              "-H", h,
              "-scale-to", thumb_size || 2048,
              "-f", page + 1,
              "-l", page + 1,
              sfn]
      ext = File.extname(thumb_filename.to_s)
      args += ["|", PNMPROGS[ext], ">", %Q('#{thumb_filename.to_s.gsub("'", "\\\\\'")}')]
      system("pdftoppm " + args.join(" "))
    }
    if File.exist?(thumb_filename) and File.size(thumb_filename) > 0
      true
    else
      false
    end
  end

  def dcraw_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-dcraw.ppm"
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(tmp_filename){|tsfn, uqtsfn|
        system("dcraw -c #{sfn} > #{tsfn}")
        FileUtils.mv(uqtsfn, tmp_filename) if File.exist?(uqtsfn) and File.expand_path(uqtsfn.to_s) != File.expand_path(tmp_filename.to_s)
      }
    }
    rv = Mimetype['image/x-portable-pixmap'].image_thumbnail(tmp_filename,
           thumb_filename, thumb_size, page, crop)
    tmp_filename.unlink if tmp_filename.exist?
    rv
  end

  def html_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-moz.png"
    system('xvfb-run', '-a', '-s', "-screen 0 1024x1024x24", 'ruby',
      File.join(File.dirname(__FILE__), 'moz-snapshooter.rb'),
      "file://" + File.expand_path(filename),
      tmp_filename.expand_path
    )
    rv = false
    if tmp_filename.exist?
      rv = Mimetype['image/png'].image_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink
    end
    rv
  end

  def web_thumbnail(url, thumb_filename, thumb_size=nil, page=0, crop='0x0+0+0')
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname + "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-moz.png"
    system('ruby',
      File.join(File.dirname(__FILE__), 'moz-snapshooter.rb'),
      url.to_s,
      tmp_filename.expand_path
    )
    rv = false
    if tmp_filename.exist?
      rv = Mimetype['image/png'].image_thumbnail(tmp_filename.expand_path, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink
    end
    rv
  end

  def fancy_video_thumbnail(filename, thumb_filename, thumb_size, page)
    require 'fileutils'
    fn = filename.to_pn
    fn.mimetype = self
    page ||= [[5.7, fn.length * 0.07].max, fn.length * 0.4].min
    thumb_size ||= 2048
    dims = fn.dimensions
    method = :mplayer_thumbnail
    if to_s =~ /flash/ || to_s == 'video/mp4'
      method = :ffmpeg_thumbnail
    end
    tfn = thumb_filename.to_pn
    tmp_dir = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-fancy"
    tmp_dir.mkdir_p
    tmp_main = tmp_dir + "cover.png"
    offset = fn.length / 57.0
    temps = (1..8).map{|i| [offset+(i-1)*(fn.length / 8.0), tmp_dir + "#{i}.png"] }
    if dims[0] >= dims[1]
      main_size = thumb_size
    else
      main_size = (dims[0] / dims[1].to_f) * thumb_size
    end
    __send__(method, fn, tmp_main, main_size, page, '0x0+0+0')
    unless tmp_main.exist?
      if method == :mplayer_thumbnail
        method = :ffmpeg_thumbnail
        __send__(method, fn, tmp_main, main_size, page, '0x0+0+0')
      end
      unless tmp_main.exist?
        __send__(method, fn, tmp_main, main_size, 0, '0x0+0+0')
      end
      if not tmp_main.exist? and method == :ffmpeg_thumbnail
        method = :mplayer_thumbnail
        __send__(method, fn, tmp_main, main_size, 0, '0x0+0+0')
      end
      unless tmp_main.exist?
        tmp_dir.rmtree
        return false
      end
    end
    ctx = Imlib2::Context.get
    ctx.blend = false
    ctx.color = Imlib2::Color::TRANSPARENT
    ctx.op = Imlib2::Op::COPY
    main_img = Imlib2::Image.load(tmp_main)
    th_w = main_img.width / 4.0
    th_h = th_w / (dims[0] / dims[1].to_f)
    th_size = [th_w, th_h].max
    x_offset = 0
    y_offset = main_img.height
    w = main_img.width
    h = main_img.height + 2*th_h
    img = Imlib2::Image.new(w, h)
    img.has_alpha = true
    img.fill_rectangle(0,0, thumb_size, h)
    img.blend!(main_img,
      0,0,
      main_img.width, main_img.height,
      (img.width-main_img.width) / 2, 0,
      main_img.width, main_img.height)
    main_img.delete!(true)
    temps.each_with_index{|(time, tmp), i|
      __send__(method, fn, tmp, th_size, time, '0x0+0+0')
      next unless tmp.exist?
      th_img = Imlib2::Image.load(tmp)
      img.blend!(th_img,
      0,0, th_img.width, th_img.height,
      x_offset + (i % 4) * th_img.width,
      y_offset + (i / 4) * th_img.height,
      th_img.width, th_img.height)
      th_img.delete!(true)
    }
    larger = [img.width, img.height].max.to_f
    if larger > thumb_size
      img.crop_scaled!(0,0, img.width, img.height,
                       (img.width / larger) * thumb_size,
                       (img.height / larger) * thumb_size)
    end
    img.save(thumb_filename)
    FileUtils.rm_r(tmp_dir)
    true
  end

  def ffmpeg_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    ffmpeg = `which ffmpeg 2>/dev/null`.strip
    ffmpeg = "ffmpeg" if ffmpeg.empty?
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-ffmpeg.png"
    secure_filename(filename){|sfn, uqsfn|
      secure_filename(tmp_filename){|tsfn, uqtsfn|
        `ffmpeg -i #{sfn} -vcodec png -f rawvideo -ss  #{page.to_s} -r 1 -an -vframes 1 -y #{tsfn} 2>/dev/null`
        FileUtils.mv(uqtsfn, tmp_filename) if File.exist?(uqtsfn) and File.expand_path(uqtsfn.to_s) != File.expand_path(tmp_filename.to_s)
      }
    }
    if tmp_filename.exist?
      Mimetype['image/png'].image_thumbnail(tmp_filename, thumb_filename,
                                            thumb_size, 0, crop)
      tmp_filename.unlink
    end
    File.exist?(thumb_filename)
  end

  def mplayer_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = thumb_filename.to_pn
    video_cache_dir = tfn.dirname +
    "videotemp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}"
    video_cache_dir.mkdir_p
    mplayer = `which mplayer 2>/dev/null`.strip
    mplayer = "mplayer" if mplayer.empty?
    fn = filename.to_pn
    aspect = fn.width / fn.height.to_f
    secure_filename(filename){|sfn, uqsfn|
      args = [mplayer, "-really-quiet", "-aspect", aspect.to_s, "-nosound",
              "-ss", page.to_s, "-vo", "jpeg:outdir=#{video_cache_dir}",
              "-frames", "2", uqsfn]
      system(*args)
    }
    j = video_cache_dir.glob("*.jpg").sort.last
    Mimetype['image/jpeg'].image_thumbnail(j, thumb_filename, thumb_size, 0, crop) if j
    video_cache_dir.rmtree
    File.exist?(thumb_filename)
  end


  # If the filename doesn't begin with a dash, passes it in
  # double-quotes with double-quotes and dollar signs in
  # filename escaped.
  #
  # Otherwise creates a link to it with a secure filename and yield the secure
  # filename. Unlinks the secure filename after yield returns.
  #
  # This is needed because of filenames like "-h".
  #
  def secure_filename(fn)
    require 'fileutils'
    filename = fn.to_s
    if filename =~ /^-/
      dirname = File.dirname(File.expand_path(filename))
      tfn = "/tmp/" + temp_filename + (File.extname(filename) || "").
            gsub(/[^a-z0-9_.]/i, '_') # PAA RAA NOO IAA
      begin
        FileUtils.ln(filename, tfn)
      rescue
        FileUtils.cp(filename, tfn) # if different fs for /tmp
      end
      yield(tfn, tfn)
    else # trust the filename to not blow up in our face
      yield(%Q("#{filename.gsub(/[$"]/, "\\\\\\0")}"), filename)
    end
  ensure
    File.unlink(tfn) if tfn and File.exist?(tfn)
  end

  def temp_filename
    "metadata_temp_#{Process.pid}_#{Thread.current.object_id}_#{Time.now.to_f}"
  end

end

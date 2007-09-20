require 'metadata'
require 'pathname'
require 'fileutils'
require 'imlib2'





module Thumbnailer
extend self

  attr_accessor :verbose, :quiet, :icon_dir

  def thumbnail(filename, thumbnail_filename, size=nil, page=nil, crop='0x0+0+0')
    mt = filename.to_pn.mimetype
    mt.thumbnail(filename.to_s, thumbnail_filename, size, page, crop)
  end

end


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
                thumb_size=nil, page=nil, crop='0x0+0+0')
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
      elsif to_s =~ /postscript/
        page ||= 0
        postscript_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /^text/
        page ||= 0
        paps_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /powerpoint|vnd\.oasis\.opendocument|msword|ms-excel|rtf|x-tex|template|stardivision|comma-separated-values|dbf|vnd\.sun\.xml/
        page ||= 0
        unoconv_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      elsif to_s =~ /^audio/
        page ||= 0
        waveform_thumbnail(filename, thumb_filename, thumb_size, page, crop)
      end
    rescue Exception => e
      puts e, e.message, e.backtrace
      false
    end or icon_thumbnail(filename, thumb_filename, thumb_size, crop)
  end

  def icon_thumbnail(filename, thumb_filename, thumb_size, crop='0x0+0+0')
    Mimetype['image/png'].image_thumbnail(icon(thumb_size), thumb_filename, thumb_size, 0, crop)
  end

  def icon(thumb_size=128)
    ancestors.map do |klass|
      Thumbnailer.icon_dir + (klass.to_s.downcase.gsub(/\//, '-')+".png")
    end.find{|pn| pn.exist? }
  end

  def image_thumbnail(filename, thumb_filename, thumb_size, page=0, crop='0x0+0+0')
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname + "tmp-#{Process.pid}-#{Thread.current.object_id}#{tfn.extname}"
    if to_s =~ /^image/
      begin
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
    filename = tfn.dirname + "tmp-#{Process.pid}-#{Thread.current.object_id}-src#{extname}"
    begin
      FileUtils.ln_s(original_filename.to_s, filename.to_s)
      filename.mimetype = self
      dims = filename.dimensions
      return false unless dims[0] and dims[1]
      larger = dims.max
      thumb_size ||= 2048
      case filename.metadata.dimensions_unit
      when 'mm'
        scale_fac = larger.mm_to_points / 72
      else
        scale_fac = larger / 72
      end
      density = thumb_size / scale_fac
      secure_filename(filename){|sfn|
        args = ["-density", density.to_s,
                "#{sfn}[#{page}]",
                "-scale", "#{thumb_size}x#{thumb_size}",
                "-crop", crop.to_s,
                tmp_filename.to_s]
        system("convert", *args)
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
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-waveform.png"
    tmp2_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-waveform2.png"
    File.open('/tmp/.waveform.lock','w') {|f|
      f.flock(File::LOCK_EX)
      secure_filename(filename.to_s){|sfn|
        system("audiothumb", "-display", ":16", sfn, tmp_filename.to_s)
      }
      f.flock(File::LOCK_UN)
    }
    rv = false
    if tmp_filename.exist?
      w,h = tmp_filename.dimensions
      system("convert #{tmp_filename.to_s.dump} -crop #{w-2}x#{h-2}+1+1 #{
              tmp2_filename.to_s.dump}")
      rv = Mimetype['image/png'].image_thumbnail(tmp2_filename, thumb_filename,
                                                 thumb_size, page, crop)
      tmp_filename.unlink
      tmp2_filename.unlink
    end
    rv
  end

  def paps_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = filename.to_pn
    tmp_filename = tfn.dirname + "#{File.basename(filename)}-temp.pdf"
    charset = filename.to_pn.metadata.charset
    unless tmp_filename.exist?
      secure_filename(filename.to_s){|sfn|
        system("iconv -f #{charset} -t utf8 #{sfn} | paps --font_scale 11 --columns 1 | ps2pdf - #{tmp_filename.to_s.dump}")
      }
    end
    rv = false
    if tmp_filename.exist?
      rv = pdf_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink unless rv
    end
    rv
  end

  def postscript_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = filename.to_pn
    tmp_filename = tfn.dirname + "#{File.basename(filename)}-temp.pdf"
    charset = filename.to_pn.metadata.charset
    unless tmp_filename.exist?
      secure_filename(filename.to_s){|sfn|
        system("ps2pdf #{sfn} #{tmp_filename.to_s.dump}")
      }
    end
    rv = false
    if tmp_filename.exist?
      rv = pdf_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink unless rv
    end
    rv
  end
  
  def unoconv_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    tfn = filename.to_pn
    tmp_filename = tfn.dirname + "#{File.basename(filename)}-temp.pdf"
    unless tmp_filename.exist?
      secure_filename(filename.to_s){|sfn|
        system("unoconv -s #{sfn} > #{tmp_filename.to_s.dump}")
      }
    end
    rv = false
    if tmp_filename.exist?
      rv = pdf_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
      tmp_filename.unlink unless rv
    end
    rv
  end
  
  def pdf_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    w,h,x,y = crop.scan(/[+-]?[0-9]+/).map{|i|i.to_i}
    secure_filename(filename.to_s){|sfn|
      args = ["-x", x, 
              "-y", y,
              "-W", w,
              "-H", h,
              "-scale-to", thumb_size || 2048,
              "-f", page + 1,
              "-l", page + 1,
              sfn]
      ext = File.extname(thumb_filename.to_s)
      args += ["|", PNMPROGS[ext], ">", thumb_filename.to_s.dump]
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
    secure_filename(filename){|sfn|
      system("dcraw -c #{sfn} > #{tmp_filename.expand_path.to_s.dump}")
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
    system('ruby',
      File.join(File.dirname(__FILE__), 'moz-snapshooter.rb'),
      "file://" + File.expand_path(filename),
      tmp_filename.expand_path
    )
    rv = Mimetype['image/png'].image_thumbnail(tmp_filename, thumb_filename, thumb_size, page, crop)
    tmp_filename.unlink if tmp_filename.exist?
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
    rv = Mimetype['image/png'].image_thumbnail(tmp_filename.expand_path, thumb_filename, thumb_size, page, crop)
    tmp_filename.unlink if tmp_filename.exist?
    rv
  end

  def fancy_video_thumbnail(filename, thumb_filename, thumb_size, page)
    fn = filename.to_pn
    fn.mimetype = self
    page ||= [[5.7, fn.length * 0.07].max, fn.length * 0.75].min
    thumb_size ||= 2048
    dims = fn.dimensions
    method = :mplayer_thumbnail
    if to_s =~ /flash/
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
    return false unless tmp_main.exist?
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
    img.save(thumb_filename)
    FileUtils.rm_r(tmp_dir)
    true
  end

  def ffmpeg_thumbnail(filename, thumb_filename, thumb_size, page, crop)
    ffmpeg = `which ffmpeg`.strip
    ffmpeg = "ffmpeg" if ffmpeg.empty?
    tfn = thumb_filename.to_pn
    tmp_filename = tfn.dirname +
    "tmp-#{Process.pid}-#{Thread.current.object_id}-#{Time.now.to_f}-ffmpeg.png"
    Thumbnailer.temp_dir.mkdir_p
    secure_filename(filename){|sfn|
      `ffmpeg -i #{sfn} -vcodec png -f rawvideo -ss  #{page.to_s} -r 1 -an -vframes 1 -y #{tmp_filename.to_s.dump} 2>/dev/null`
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
    mplayer = `which mplayer32`.strip
    mplayer = `which mplayer`.strip if mplayer.empty?
    mplayer = "mplayer" if mplayer.empty?
    secure_filename(filename){|sfn|
      fn = sfn.to_pn
      fn.mimetype = self
      aspect = fn.width / fn.height.to_f
      system(mplayer, "-really-quiet", "-aspect", aspect.to_s, "-nosound",
             "-ss", page.to_s, "-vo", "jpeg:outdir=#{video_cache_dir}",
             "-frames", "10", sfn)
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
  def secure_filename(filename)
    if filename =~ /^-/
      dirname = File.dirname(File.expand_path(filename))
      tfn = "/tmp/" + temp_filename + (File.extname(filename) || "").
            gsub(/[^a-z0-9_.]/i, '_') # PAA RAA NOO IAA
      begin
        FileUtils.ln(filename, tfn)
      rescue
        FileUtils.cp(filename, tfn) # different fs for /tmp
      end
      yield(tfn)
    else # trust the filename to not blow up in our face
      yield(%Q("#{filename.gsub(/[$"]/, "\\\\\\0")}"))
    end
  ensure
    File.unlink(tfn) if tfn and File.exist?(tfn)
  end

  def temp_filename
    "metadata_temp_#{Process.pid}_#{Thread.current.object_id}_#{Time.now.to_f}"
  end

end

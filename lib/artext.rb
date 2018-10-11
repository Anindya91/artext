require "artext/version"
require "open-uri"
require "httparty"
require "nokogiri"
require "mini_magick"
require "fastimage"
require "addressable"

module Artext

  USER_AGENT = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

  def self.extract(url)
    url = (url =~ /^(http|https):\/\/(.)*/i) ? url : "http://#{url}"
    return {:url => url, :data => [], :article => []} if ((url =~ /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix).nil?)
    begin
      res = HTTParty.get(url, headers: {"User-Agent" => USER_AGENT})
      raise Exception.new("Unable to crawl URL") if res.code != 200
      doc = Nokogiri::HTML(res)
    rescue Exception => e
      doc = Nokogiri::HTML(open(url, "User-Agent" => USER_AGENT))
    end
    data = get_data_from_url(doc, url)
    article = get_article_from_url(doc, url, data[:type])
    data[:type] = "image" if (article[:score] == 1)
    response = {:url => url, :data => [data], :article => [article]}
  end

  def self.get_data_from_url(doc, url)
    og_image = doc.search("//meta[@property='og:image' or @name='og:image']")
    og_images = []
    if !is_blank?(og_image)
      og_image.each do |ogi|
        if !is_blank?(ogi["content"])
          image = ogi["content"]
          if (image =~ /^\/\/(.)*/)
            uri = URI.parse(url)
            image = "#{uri.scheme}:#{image}"
          elsif (image =~ /^\/(.)*/)
            uri = URI.parse(url)
            image = File.join("#{uri.scheme}://#{uri.host}", image)
          end
          og_images << image
        end
      end
    end
    # Try to get the best image based on heuristics
    image = get_best_image(og_images)

    og_title = doc.search("//meta[@property='og:title' or @name='og:title']")
    if (!is_blank?(og_title) && !is_blank?(og_title[0]["content"]))
      clip_title = og_title[0]["content"]
    else
      page_title = doc.search("//title")[0]
      clip_title = page_title.text if !is_blank?(page_title)
    end

    tags = []
    possible_tags = doc.xpath('//meta[contains(@name, "tag") or contains(@name, "keyword") or contains(@property, "tag") or contains(@property, "keyword")]')
    possible_tags.each{|e| tags << e["content"].split(',') if (!e["content"].nil?)}
    tags = tags.flatten.map(&:strip).uniq!

    type = doc.search("//meta[@property='og:type' or @name='og:type']")
    type = is_blank?(type) ? nil : type[0]["content"]

    favicon = "http://www.google.com/s2/favicons?domain_url=#{url}"
    theme = get_dominant_color(favicon)

    res = {:image => image, :title => clip_title, :tags => tags, :type => type, :favicon => favicon, :theme => theme}
  end

  def self.get_author_and_date(doc)
    authors = []
    possible_authors = doc.xpath('//meta[@property="author" or @name="author"]')
    possible_authors.each {|a| authors << a["content"] if (!is_blank?(a["content"]))}

    date = nil
    possible_dates = doc.xpath('//meta[contains(@property, "date") or contains(@name, "date")]')
    if (!is_blank?(possible_dates))
      possible_dates.each do |po|
        if (po["content"][0..3].to_i > 2000)
          date = po["content"] if (!is_blank?(po["content"]))
          break
        end
      end
    end
    if (date.nil?)
      possible_dates = doc.xpath('//*[contains(@datetime, "2015")]')
      date = possible_dates.first.attribute("datetime").value if (!is_blank?(possible_dates))
    end
    if (!date.nil?)
      datetime = date.split.join(" ")[0..9].split("-")
      t = Time.new(datetime[0], datetime[1], datetime[2])
      date = "#{Date::MONTHNAMES[t.month]} #{t.day}, #{t.year}"
    end
    return {:date => date, :authors => authors}
  end

  def self.get_best_image(images)
    return nil if (is_blank?(images))
    return images[0] if (images.size == 1)
    # reject logo or similar images
    refined_images = images.reject{|i| i =~ /logo|fallback/i}
    return refined_images[0] if (refined_images.size == 1)
    refined_images = images if is_blank?(refined_images)
    dimensions = []
    refined_images.each do |i|
      type = FastImage.type(Addressable::URI.escape(i))
      size = FastImage.size(Addressable::URI.escape(i))
      return i if((type == :gif) && (size && size[0] > 299 && size[1] > 199))
      dimensions << {:x => size[0], :y => size[1], :image => i} if !size.nil?
    end
    image = is_blank?(dimensions) ? nil : dimensions.max_by{|d| d[:x]}[:image]
    return image
  end

  def self.get_article_from_url(doc, url, type)
    dates = get_author_and_date(doc)
    article = doc.search("//article")
    score = 0.9
    article = [] if (article.count == 1 && article.text.split.join(" ").length < 500)
    if (article.count > 1)
      article = get_correct_article(article)
      score = 0.8
    end
    if (is_blank?(article))
      article = find_article(doc)
      score = 0.6
    end
    if (is_blank?(article))
      # image url
      begin
        html = doc.to_html
        raise Exception.new("Image URL") if is_blank?(html)
        return {:body => "", :text => "", :images => [], :score => 0}
      rescue Exception => e
        return {:body => "<figure><img src=\"#{url}\"></figure>", :text => "", :images => [url], :score => 1}
      end
    else
      article = remove_unwanted_items_from(article)
      article, score = find_relevant(article, score)
      score = score - 0.5 if (type != "article")
      if (score > 0.9)
        html, imgs = iteratively_clean(article, "", [], score)
      else
        html, imgs = recursively_clean(article, "", [], score)
      end
      response = {:body => html, :text => article.text.split.join(" "), :images => imgs, :score => score}.merge(dates)
    end
  end

  def self.find_relevant(article, score)
    p_elems = article.search("p")
    total_p = p_elems.count
    rel = article
    max_p = 0
    last_p = 0
    if (!is_blank?(p_elems))
      while (p_elems[0].text != article.text || p_elems[0].attribute("class") != article.attribute("class"))
        parent_elems = p_elems.map {|p| p.parent()}
        parent_elems.each do |ps|
          if (ps.search("p").count > max_p)
            max_p = ps.search("p").count
            rel = ps
          end
        end
        if ((last_p > 5 && last_p == max_p) || total_p - max_p < 2)
          score = 0.95 if (score < 1)
          break
        end
        last_p = max_p
        p_elems = parent_elems
      end
    end
    return rel, score
  end

  def self.iteratively_clean(element, html, images, score)
    html = ""
    imgs = []
    element.children.each do |elem|
      tv, ti = get_element_html(elem, [], score)
      html = html + tv if (!is_blank?(tv))
      imgs = imgs + ti if (!is_blank?(ti))
    end
    imgs.uniq!
    return html, imgs
  end

  def self.recursively_clean(element, html, images, score)
    allowable = ["p", "figure", "a", "h1", "h2", "h3", "h4", "text"]
    if (is_blank?(element.children) || (element.class != Nokogiri::XML::NodeSet && (allowable.include?(element.name))))
      tv, ti = get_element_html(element, [], score)
      html = html + tv if (!is_blank?(tv))
      images = images + ti
      images.uniq!
    else
      if (element.class != Nokogiri::XML::NodeSet && (element.name == "header" || element.name == "footer"))
        # Eat it
      elsif (element.class != Nokogiri::XML::NodeSet && element.name == "div" && !is_blank?(element.attribute("class")) && element.attribute("class").value.downcase.include?("meta") && element.text.split.join(" ").length < 300)
        #Eat it
      elsif (element.class != Nokogiri::XML::NodeSet && element.name == "section" && score > 0.9)
        #Eat it
      elsif (element.class != Nokogiri::XML::NodeSet && element.name == "ul" && score > 0.9)
        #Eat it
      elsif (element.class != Nokogiri::XML::NodeSet && element.name == "ol" && score > 0.9)
        #Eat it
      else
        element.children.each do |art|
          html, images = recursively_clean(art, html, images, score)
        end
      end
    end
    return html, images
  end

  def self.get_element_html(element, images, score)
    if (element.name == "a")
      # Eat it
    elsif (element.name == "img")
      img = get_valid_image(element)
      if (!is_blank?(img))
        tv = "<figure><img src=\"#{img}\"></figure>"
        images = images + [img]
      end
    elsif (element.name == "h1" || element.name == "h2" || element.name == "h3" || element.name == "h4")
      tv = "<h2>#{element.text.split.join(" ")}</h2>" if (!is_blank?(element.text.split.join(" ")))
    elsif (element.name == "p")
      p_elem, ti = extractp(element, score)
      tv = "<p>#{p_elem}</p>" if (!is_blank?(p_elem))
      images = images + ti if (!is_blank?(ti))
    elsif (element.name == "figure")
      cap = element.search("figcaption").text.split.join(" ")
      cap = is_blank?(cap) ? "" : "<figcaption>#{cap}</figcaption>"
      tv, ti = figurehandle(element, "", [])
      tv = "<figure>#{tv}#{cap}</figure>" if (!is_blank?(tv))
      images = images + ti
    elsif (element.name == "text")
      tv = element.text.split.join(" ")
      tv = nil if tv == "advertisement"
      tv = "<p class\"inline\">#{tv}</p>" if (!is_blank?(tv))
    elsif (element.name == "i")
      tv = element.text.split.join(" ")
      tv = "<i>#{tv}</i>" if (!is_blank?(tv))
    elsif (element.name == "ol" || element.name == "ul")
      tv, ti = listhandle(element)
      images = images + ti
    elsif (element.name == "div" || element.name == "span")
      html = ""
      imgs = []
      element.children.each do |elem|
        tv, ti = get_element_html(elem, [], score)
        html = html + tv if (!is_blank?(tv))
        imgs = imgs + ti if (!is_blank?(ti))
      end
      tv = html
      images = imgs
    end
    return tv, images
  end

  def self.get_valid_image(element)
    if (!is_blank?(element))
      tsrc1 = nil
      search_in = ["data-image", "data-original", "srcset", "data-src", "datasrc", "rel:bf_image_src", "src"]
      search_in.each do |search|
        tsrc = element.attribute(search)
        if (!is_blank?(tsrc))
          tsrc1 = tsrc.value
          tsrc1 = tsrc1.split(",").first.split(" ")[0] if (search == "srcset")
          break
        end
      end
      if (!is_blank?(tsrc1))
        tsrc1 = "http:" + tsrc1 if (tsrc1[0..1] == "//")
        tv_size = FastImage.size(Addressable::URI.escape(tsrc1))
        if (!tv_size.nil? && (tv_size[0] > 100 || tv_size[1] > 100))
          return tsrc1
        end
      end
    end
    return ""
  end

  def self.extractp(element, score)
    p_elem = nil
    imgs = []
    as = element.search("a")
    if (!is_blank?(as) && element.text == as.text && score < 0.8)
      return nil
    end
    p_elem, imgs = phandle(element, "", []) if (!is_blank?(element))
    return p_elem, imgs
  end

  def self.phandle(element, html, images)
    if (!is_blank?(element.children) && !(element.name == "a" && is_blank?(element.search("img"))))
      element.children.each do |elem|
        html, images = phandle(elem, html, images)
      end
    end
    if (element.name == "img")
      img = get_valid_image(element)
      if (!is_blank?(img))
        html = "</p><figure><img src=\"#{img}\"></figure><p>"
        images << img
      end
    elsif (element.name == "a")
      html = html + " <a href=\"#{element.attribute("href").value if (!is_blank?(element.attribute("href")))}\">#{element.text.split.join(" ")}</a> "
    elsif (element.name == "text")
      html = html + element.text.split.join(" ")
    elsif (element.name == "br")
      html = html + "<br>"
    elsif (element.name == "p" && is_blank?(html))
      html = element.text.split.join(" ")
    end
    return html, images
  end

  def self.figurehandle(element, html, images)
    if (element.name == "img" || (!is_blank?(element.attribute("class")) && element.attribute("class").value.include?("js-delayed-image-load")))
      img = get_valid_image(element)
      if (!is_blank?(img))
        html = html + "<img src=\"#{img}\">"
        images << img
      end
    elsif (is_blank?(element.children))
      return html, images
    else
      element.children.each do |elem|
        html, images = figurehandle(elem, html, images)
      end
    end
    return html, images
  end

  def self.listhandle(element)
    html = ""
    imgs = []
    li_elems = element.search("li")
    li_elems.each do |elem|
      tv, ti = recursively_clean(elem, "", [], 0.95)
      html = html + "<li>#{tv}</li>" if (!is_blank?(tv))
      imgs = imgs + ti if (!is_blank?(ti))
    end
    if (element.name == "ul")
      html = "<ul>#{html}</ul>" if (!is_blank?(html))
    elsif (element.name == "ol")
      html = "<ol>#{html}</ol>" if (!is_blank?(html))
    end
    return html, imgs
  end

  def self.find_article(doc)
    article = doc.xpath('//*[@*="articleBody"]')
    article = doc.xpath('//*[contains(@class, "article")]') if (is_blank?(article) || article.text.split.join(" ").length < 450)
    article = doc.xpath('//*[contains(@class, "body")]') if (is_blank?(article) || article.text.split.join(" ").length < 450)
    return article
  end

  def self.get_correct_article(articles)
    articles.each do |article|
      if (article.text.split.join(" ").length > 200)
        return article
      end
    end
    return nil
  end

  def self.remove_unwanted_items_from(article)
    unwanted_elements = ["//script", "//comment()", "//aside", ".aside", "iframe", "//noscript", "//form", "//header", "//footer"]
    unwanted_elements.each do |elem|
      article.search("#{elem}").remove
    end
    removable_elements = ["comment", "social", "advertisement", "share"]
    removable_elements.each do |rem|
      article.xpath("//*[contains(@*, '#{rem}')]").remove
    end
    return article
  end

  def self.get_dominant_color(url)
    image = MiniMagick::Image.open(url)
    color = image.run_command("convert", image.path, "-format", "%c\n",  "-colors", 1, "-depth", 8, "histogram:info:").split(' ')
    return color[Hash[color.map{|h| h =~ /^#/}.map.with_index.to_a][0]][0..6]
  end

  def self.is_blank?(value)
    if (value.class == Nokogiri::XML::Element || value.class == Nokogiri::XML::Attr)
      return (value.nil? || value.blank?)
    else
      return (value.nil? || value.empty?)
    end
  end

end

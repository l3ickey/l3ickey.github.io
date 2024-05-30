module Jekyll
  class CustomExcerpt < Generator
    def generate(site)
      site.posts.docs.each do |post|
        post.data['excerpt'] = get_custom_excerpt(post)
      end
    end

    def get_custom_excerpt(post)
      content = post.content.gsub(/\r\n|\r|\n/, ' ')
      excerpt_length = post.site.config['excerpt_length'] || 50
      content.split[0...excerpt_length].join(' ') + '...'
    end
  end
end


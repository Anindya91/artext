# Artext

Artext is a gem to extract articles from webpages. It removes all advertisement and additional content, and only shows the core content of the article. It can be helpful for applications that show article view.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'artext'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install artext

## Usage

```ruby
require 'artext'

url = "http://techcrunch.com/2015/07/07/meet-lynx-an-app-for-sharing-links-with-friends/"

Artext.extract(url)
```

## Response

```ruby
response = 
	{
		:url => "http://techcrunch.com/2015/07/07/meet-lynx-an-app-for-sharing-links-with-friends/"
		:data => [{
				:image => "OG IMAGE",
				:title => "OG TITLE",
				:tags => ["KEYWORDS AND TAGS"],
				:type => "OG TYPE",
				:favicon => "FAVICON URL",
				:theme => "DOMINANT COLOR IN THE FAVICON",
			}]
		:article => [{
				:body => "SANITIZED HTML OF THE CORE CONTENT",
				:text => "TEXT OF THE CORE CONTENT",
				:images => ["ARRAY OF IMAGE URLS IN THE SANITIZED HTML"],
				:date => "PUBLISHING DATE OF THE ARTICLE",
				:author => ["PUBLISHING AUTHOR(s)"],
				:score => SCORE BETWEEN 0 AND 1 RELATING TO HOW SUCCESSFULLY THE CONTENT WAS EXTRACTED,
			}]
	}
```

## Contributing

Thank you @amitsaxena for your inputs.

1. Fork it ( https://github.com/[my-github-username]/artext/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

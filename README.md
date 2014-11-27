# Redcrumbs

[![Build Status](https://travis-ci.org/JonMidhir/Redcrumbs.svg?branch=version_5.0)](https://travis-ci.org/JonMidhir/Redcrumbs)
[![Code Climate](https://codeclimate.com/github/JonMidhir/Redcrumbs/badges/gpa.svg)](https://codeclimate.com/github/JonMidhir/Redcrumbs)
[![Test Coverage](https://codeclimate.com/github/JonMidhir/Redcrumbs/badges/coverage.svg)](https://codeclimate.com/github/JonMidhir/Redcrumbs)
[![Dependency Status](https://gemnasium.com/JonMidhir/Redcrumbs.svg)](https://gemnasium.com/JonMidhir/Redcrumbs)

Fast and unobtrusive activity tracking of ActiveRecord models using Redis and DataMapper.

Introducing activity feeds to your application can come at significant cost, increasing the number of writes to your primary datastore across many controller actions - sometimes when previously only reads were being performed. Activity items have their own characteristics too; they're often not mission critical data, expirable over time and queried in predictable ways.

It turns out Redis is an ideal solution. Superfast to write to and read from and with Memcached-style key expiration built in, leaving your primary database to focus on the business logic.

Redcrumbs is designed to make it trivially easy to start generating activity feeds from your application using Redis as a back-end.


## Installation

You'll need access to a [Redis](http://redis.io) server running locally, remotely or from a managed service; such as [Redis Labs](https://redislabs.com/). 

Add the Gem to your Gemfile:

```ruby
gem 'redcrumbs'
```

Then run the generator to create the initializer file.

```sh
$ rails g redcrumbs:install
```

Done! Look in `config/initializers/redcrumbs.rb` for customisation options.


## Getting Started

Start tracking a model by adding `redcrumbed` to the class:

```ruby
class Game < ActiveRecord::Base
  redcrumbed :only => [:name, :highscore]
  
  validates :name, :presence => true
  validates :highscore, :presence => true
end
```

That's all you need to get started. `Game` objects will now start generating activities when their `name` or `highscore` attributes are updated.


```ruby
game = Game.last
=> #<Game id: 1, name: "Paperboy" ... >

game.update_attributes(:name => "Paperperson")
=> #<Game id: 1, name: "Paperperson" ... >
```

Activities are objects of class `Crumb` and contain all the data you need to find out about what has changed in the update.


```ruby
crumb = game.crumbs.last
=> #<Crumb id: 53 ... >

crumb.modifications
=> {"name" => ["Paperboy", "Paperperson"]}

```

The `.crumbs` method shown here is available to any class that is `redcrumbed` and is just a DataMapper collection. You can use it to construct any queries you like. For example, to get the last 10 activities on `game`:

```ruby
game.crumbs.all(:order => :created_at.desc, :limit => 10)
```

## Creating a HTML activity feed

Redcrumbs doesn't provide any helpers to turn crumbs into translated text or HTML views but this is extremely easy to do once you're set up and creating activities.

Now that we know how to query activities associated with an object we just need to create a helper to translate this into readable text or HTML. Crumbs have a `subject` association that gives you access to the original object. This is useful when you need access to attributes that aren't in the modifications hash.

Here's an example of a text simple helper:

```ruby
module ActivityHelper
  def activity_text_from(crumb)
    modifications = crumb.modifications
    
    message = 'Someone '
    
    fragments = []
    fragments << "set a highscore of #{modifications['highscore']}" if modifications.has_key?('highscore')
    
    if modifications.has_key?('name')
      fragments << "renamed #{modifications['name']} to #{modifications['name']}"
    else
      fragments[0] += " at #{crumb.subject.name}"
    end
    
    message += fragments.to_sentence
    message += '.'
  end
end
```

And an example of its output:

```
"Someone renamed Paperboy to Paperperson."
"Someone set a highscore of 19840 at Paperperson."
"Someone set a highscore of 21394 at Paperperson and renamed Paperperson to I WIN NOOBS."
```


## User context

Crumbs can also track the user that made the change (creator), and even a secondary user affected by the change (target). By default the creator is considered to be the user associated with the object:

```
> user = User.find(2)
=> #<User id: 2, name: "Jon" ... >

> venue = user.venues.last
=> #<Venue id: 1, name: "City Hall, Belfast", user_id: 2 ... >

> venue.update_attributes(:name => "Halla na Cathrach, Bhéal Feirste")
=> #<Venue id: 1, name: "Halla na Cathrach, Bhéal Feirste", user_id: 2 ... >

> crumb = venue.crumbs.last
=> #<Crumb id: 54 ... >

> crumb.modifications
=> {"name" => ["City Hall, Belfast", "Halla na Cathrach, Bhéal Feirste"]}

> crumb.creator
=> #<User id: 2, name: "Jon" ... >

# and really cool, returns a limited (default 100) array of crumbs affecting a user in reverse order:
> user.crumbs_as_user(:limit => 20)
=> [#<Crumb id: 64 ... >, #<Crumb id: 53 ... >, #<Crumb id: 42 ... > ... ]

# or if you just want the crumbs created by the user
> user.crumbs_by

# or affecting the user
> user.crumbs_for

```

You can customise just what should be considered a creator or target globally across your app by editing a few lines in the redcrumbs initializer. Or you can override the creator and target methods if you want class-specific control:

```
class User < ActiveRecord::Base
  belongs_to :alliance
  has_many :venues
end

class Venue < ActiveRecord::Base
  redcrumbed :only => [:name, :latlng]
  
  belongs_to :user
  
  validates :name, :presence => true
  validates :latlng, :uniqueness => true
  
  def creator
    user.alliance
  end
end
```

## Conditional control

You can pass `:if` and `:unless` options to the redcrumbed method to control when an action should be tracked in the same way you would for an ActiveRecord callback. For example:

```
class Venue < ActiveRecord::Base
  redcrumbed :only => [:name, :latlng], :if => :has_user?
  
  def has_user?
    !!user_id
  end
end
```

## Attribute storage

It's not best practice but since the emphasis is on easing the load on our main database we have bent a few rules in order to reduce the calls on the database to, ideally, zero. In any given app you may be tracking several models and this results in a lot of SQL we could do without.

#### Versions >= 0.3.0

`redcrumbed` accepts a `:store` option to which you can pass a hash of options similar to that of the ActiveRecord `as_json` method. These are attributes of the subject that you'd like to store on the crumb object itself. Use it sparingly if you know that, for example, you are only ever going to really use a couple of attributes of the subject and you want to avoid loading the whole thing from the database.

Examples:

```
class Venue
  redcrumbed :only => [:name, :latlng], :store => {:only => [:id, :name]}
end
```

```
class Venue
  redcrumbed :only => [:name, :latlng], :store => {:except => [:updated_at, :created_at]}
end
```

```
class Venue
  redcrumbed :only => [:name, :latlng], :store => {:only => [:id, :name], :methods => [:checkins]}
end
```

#### Versions  < 0.3.0

`redcrumbed` accepts a `:store` option to which you can pass an array of attributes of the subject that you'd like to store on the crumb object itself. Use it sparingly if you know that, for example, you are only ever going to really use a couple of attributes of the subject and you want to avoid loading the whole thing from the database.

```
class Venue
  redcrumbed :only => [:name, :latlng], :store => [:id, :name]
end
```

#### Using the stored object

So now if you call `crumb.subject` instead of loading the Venue from your database it will instantiate a new Venue with the only the attributes you have stored. You can always retrieve the original by calling `crumb.full_subject`.

_ If you plan to use the `methods` option to store data on the Crumb you should only use it to store attr_accessors unless you won't be instantiating the subject itself _

#### Creator and Target storage

As you might expect, you can also do this for the creator and target of the crumb. See the redcrumbs.rb initializer for how to set this as a global configuration.


## To-do

Lots of refactoring, tests and new features.

## Testing

Running tests requires a redis server to be running on the local machine with access over port 6379.
Run tests with `rspec`.

## License

Created by John Hope ([@midhir](http://www.twitter.com/midhir)) (c) 2012 for Project Zebra ([@projectzebra](http://www.twitter.com/projectzebra)). Released under MIT License (http://www.opensource.org/licenses/mit-license.php).

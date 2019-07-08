# Exchange [![CircleCI](https://circleci.com/gh/artsy/exchange.svg?style=svg)](https://circleci.com/gh/artsy/exchange)  [![Coverage Status](https://coveralls.io/repos/github/artsy/exchange/badge.svg)](https://coveralls.io/github/artsy/exchange)
Exchange aspires to be responsible for the various types of e-commerce interactions available on the Artsy platform. It's currently a prototype, with legacy e-commerce still handled by Gravity. It uses Ruby, Rails, Postgresql, and exposes a [GraphQL](http://graphql-ruby.org/) API.

## Meta

* State: production
* Production: https://exchange.artsy.net, [Admin Dashboard](https://exchange.artsy.net/admin) | [Sidekiq Dashboard](https://exchange.artsy.net/admin/sidekiq)
* Staging: https://exchange-staging.artsy.net, [Admin Dashboard](https://exchange-staging.artsy.net/admin) | [Sidekiq Dashboard](https://exchange-staging.artsy.net/admin/sidekiq)
* GitHub: https://github.com/artsy/exchange/
* Point People: [@ashkan18][ashkan18], [@williardx][williardx]
* CI/Deploys: [CircleCi](https://circleci.com/gh/artsy/exchange); merged PRs to `artsy/exchange#master` are automatically deployed to staging; PRs from `staging` to `release` are automatically deployed to production. [Start a deploy...](https://github.com/artsy/exchange/compare/release...staging?expand=1)

## Setup

* Fork the project to your GitHub account

* Clone your fork:
  ```
  $ git clone git@github.com:your-github-username/exchange.git
  ```

* Install bundles:
  ```
  $ bundle install
  ```

## Tests

Once setup, you can run the tests like this:

```
$ bundle exec rspec
```

## Starting Server
If this is your first time starting the app, make sure your database is setup first by running:
```shell
rails db:create
rails db:setup
```

Then run Procfile.dev via foreman to start the web (rails) and worker (sidekiq)
services:

```bash
foreman start -f Procfile.dev
```

## Did You Change Models?

### Papertrail Audit Logging

As Exchange persists important financial information, we use the [PaperTrail gem](https://github.com/paper-trail-gem/paper_trail) to maintain a log of data changes to important models within the main relational database.

Exchange implements a slightly-customized, but supported, installation of PaperTrail. By default, PaperTrail writes audit log records to a single `versions` table. In Exchange, we write audit logs into model-namespaced tables. For example, the audit log for `Order` records are in the `order_versions` table and the audit log for `Offer` records are in the `offer_versions` table.

Why do we do this? It'll allow PostgreSQL to query across smaller sets of data when operating against the audit log for a particular model.

How to implement this pattern for future models:

1. Include the versioned model shared example in the spec for your model:

  ```ruby
    # spec/models/foo_spec.rb
    describe Foo, type: :model do
      ...
      it_behaves_like 'a papertrail versioned model', :foo
      ...
    end
  ```

1. Ensure that a Fabricator factory exists for your model:

  ```ruby
    # spec/fabricators/foo_fabricator.rb
    Fabricator(:foo) do
      # define enough attributes to have a `valid?` instance of `Foo`
    end
  ```

1. Include the customized PaperTrail DSL in your model (provides #versions):

  ```ruby
    # app/models/foo.rb
    class Foo < ApplicationRecord
      has_paper_trail versions: { class_name: 'PaperTrail::FooVersion' }
      ...
    end
  ```
1. Define the model-specific version class:

  ```ruby
    # app/models/paper_trail/foo_version.rb
    module PaperTrail
      class FooVersion < PaperTrail::Version
        self.table_name = :foo_versions
      end
    end
  ```

1. Create the model-specific versions table:

  ```sh
    bundle exec rails generate migration add_foo_versions
  ```

  ```ruby
    # db/migrate/timestamp_add_foo_versions.rb
    class AddFooVersions < ActiveRecord::Migration[5.2]
      def change
        create_table :foo_versions do |t|
          t.string   :item_type, null: false
          t.uuid     :item_id,   null: false
          t.string   :event,     null: false
          t.string   :whodunnit
          t.jsonb    :object
          t.jsonb    :object_changes
          t.datetime :created_at
        end

        add_index :foo_versions, %i[item_type item_id]
      end
    end
  ```

**N.B: If the model being versioned uses a different type of primary key (i.e. integer instead of UUID), feel free to change the `t.uuid` to `t.#{another_type}`**

#### References

- Exchange PR with initial implementation: https://github.com/artsy/exchange/pull/314
- PaperTrail docs on Custom Version Classes: https://github.com/paper-trail-gem/paper_trail/tree/091612fb565c5fa71aee828fa575cc4e4c180f28#6a-custom-version-classes


### Analytics Notification
If you changed something in the `/models` make sure to inform #data (analytics) team about it in case it impacts their reports.



## Did You Change GraphQL Schema?
Metaphysics is the current consumer of Exchange GraphQL schema and keeps a copy of latest schema in https://github.com/artsy/metaphysics/tree/master/src/data, if you have changed Exchange GraphQL schema, make sure you also update the copy of this schema in Metaphysics. In order to do so follow these steps:
1) In exchange run
```shell
rake graphql:schema:idl
```
2) rename `schema.graphql` file generated ☝🏼 to `exchange.graphql`
```shell
mv schema.graphql exchange.graphql
```
3) copy file above to your local update Metaphysics under `src/data` and make a PR to Metaphysics with this change. 

There is a guide on how to add exchange operations to Metaphysics [here](https://github.com/artsy/metaphysics/blob/master/docs/create_exchange_operations.md)


## Talking to Exchange 🤑
In order to talk to Exchange GraphQL endpoint:
- Copy `.env.example` to `.env`
- Update the `REPLACE_ME` values in the `.env` file. You can reference the values used on staging with `hokusai staging env get`.
- Install `dotenv` by `gem install dotenv`
- Start local server `dotenv rails s`
- If you work at Artsy, get proper Gravity User Token following [these instructions](https://github.com/artsy/gravity/blob/master/doc/ApiAuthentication.md#fetching-a-user-jwt-for-the-target-service) (the client application name is "Exchange Staging").
- Install and run [GraphiQL](https://github.com/skevy/graphiql-app) app `brew cask install graphiql`
- In GraphiQL app, go to http://localhost:3000/api/graphql, you should ge unauthorized error
- Edit HTTP Headers and add `Authorization` header and set it to `Bearer <token>` where `<token>` is your Gravity token generated few steps above.

### Working at Artsy?

#### GraphQL Queries
We share our GraphQL sample queries using [Insomnia](https://insomnia.rest/) shared workspace. You can import latest queries from [environments_and_requests.json](https://github.com/artsy/potential/tree/master/insomnia)

#### Get Access To Exchange
Access to Exchange Admin is limited to users with the role "Sales Admin". Ask someone with Role Manager permissions to grant your user "Sales Admin" permissions.

### Debugging
Something went wrong? Ideally in the JSON response returned from Exchange there will be enough info to describe what went wrong. In case that was not useful, you can:

1) Check [Sentry](https://sentry.io) (password in 1Pass) and look for Exchange (staging or production) and see the error.
2) Follow exchange logs by doing
```shell
hokusai staging logs -f
```

If you think there is something we could improve in this error case, feel free to [open an issue](https://github.com/artsy/exchange/issues/new) with details about what you did and what went wrong.


[ashkan18]: https://github.com/ashkan18
[williardx]: https://github.com/williardx


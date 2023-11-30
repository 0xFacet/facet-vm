# Welcome to the Facet VM!

The Facet VM is an app that interprets certain special ethscriptions as computer commands direct at computer programs called Dumb Contracts.

The VM handles logic, validation, and state persistance and exposes everything it does via an API.

You can interact with the VM using the [FacetScan](https://github.com/0xfacet/facetscan).

## Installation Instructions

The VM is a Ruby on Rails app. To install it, follow these steps:

Run this command inside the directory of your choice to clone the repository:

```!bash
git clone https://github.com/0xfacet/facet-vm
```

If you don't already have Ruby Version Manager installed, install it:

```bash
\curl -sSL https://get.rvm.io | bash -s stable
```

You might need to run this if there is an issue with gpg:

```bash
gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
```

Now install ruby 3.2.2 which the VM uses:

```bash
rvm install 3.2.2
```

On a Mac you might run into an issue with openssl. If you do you might need to run something like this:

```bash
rvm install 3.2.2 --with-openssl-dir=$(brew --prefix openssl@1.1)
```

Install the gems (libraries) the app needs:

```bash
bundle install
```

The VM runs on postgres, so install it if you don't already have it:

```bash
brew install postgresql
```

Create the database:

```bash
rails db:create
```

Migrate the database schema:

```bash
rails db:migrate
```

Set up your env vars by renaming `.sample.env` to `.env`.

Run the tests to make sure everything is set up correctly:

```bash
rspec
```

Now run the process to sync ethscriptions from the indexer to your local database and execute the contract commands:

```bash
bundle exec clockwork config/clock.rb
```

And then in another terminal:

```bash
bundle exec clockwork config/processor_clock.rb
```

You'll want to keep these two running in the background so your copy of the VM processes all new contract interactions.

Now start the web server on a port of your choice, for example 4000:

```bash
rails s -p 4000
```

Now you can see all your contract interactions at `http://localhost:4000/transactions` and call contract static functions at `http://localhost:4000/contracts/:contract_id/static-call/:function_name`.

If you want to debug your app you can run `rails c` to open up a console. Once in the console you can run things like `Ethscription.count` to see the total number of ethscriptions that have been processed and `TransactionReceipt.all` to list all contract transaction receipts.

## Creating Dumb Contracts

Now that you're set up you can try the main attraction: creating your own Dumb Contracts. Dumb Contracts live in `app/models/contracts`. You can edit and create them without touching any other part of the codebase. [See these docs for more](https://docs.facet.org)!

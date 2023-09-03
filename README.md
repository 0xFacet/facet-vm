# Welcome to the Ethscriptions VM Server!

The Ethscriptions VM is an app that interprets certain special ethscriptions as computer commands direct at computer programs called Dumb Contracts.

The VM handles logic, validation, and state persistance and exposes everything it does via an API.

You can interact with the VM using the [Ethscriptions VM Client](https://github.com/ethscriptions-protocol/ethscriptions-vm-client).

## Installation Instructions

The VM is a Ruby on Rails app. To install it, follow these steps:

Run this command inside the directory of your choice to clone the repository:

```!bash
git clone https://github.com/ethscriptions-protocol/ethscriptions-vm
```

If you don't already have Ruby Version Manager installed, install it:

```bash
\curl -sSL https://get.rvm.io | bash -s stable
```

You might need to run this if there is an issue with gpg:

```bash
gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
```

Now install ruby 3.1.4 which the VM uses:

```bash
rvm install 3.1.4
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

Set up your env vars by renaming `.sample.env` to `.env`. The most important env var is `INDEXER_API_BASE_URI`. This is the indexer you will use to get ethscriptions relevant to the Ethscriptions VM. By default it is set to use the ethscriptions.com indexer, which is free.

Run the tests to make sure everything is set up correctly:

```bash
rspec
```

Now run the process to sync ethscriptions from the indexer to your local database and execute the contract commands:

```bash
bundle exec clockwork config/clock.rb
```

You'll want to keep this running in the background so your copy of the VM processes all new contract interactions.

Now start the web server on a port of your choice:

```bash
rails s -p PORT
```

Now you can see all your contract interactions at `http://localhost:4000/contracts/:contract_id/call-receipts` and call contract static functions at `http://localhost:4000/contracts/:contract_id/static-call/:function_name`.

If you want to debug your app you can run `rails c` to open up a console. Once in the console you can run things like `Ethscription.count` to see the total number of ethscriptions that have been processed and `ContractCallReceipt.all` to list all contract call receipts.

## Creating Dumb Contracts

Now that you're set up you can try the main attraction: creating your own Dumb Contracts. Dumb Contracts live in `app/models/contracts`. You can edit and create them without touching any other part of the codebase. [See these docs for more](https://docs.ethscriptions.com/v/ethscriptions-vm/getting-started/welcome-to-ethscriptions-vm)!




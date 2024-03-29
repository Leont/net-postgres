[![Actions Status](https://github.com/Leont/net-postgres/workflows/test/badge.svg)](https://github.com/Leont/net-postgres/actions)

Name
====

Net::Postgres - an asynchronous postgresql client

Synopsis
========

```raku
use v6.d;
use Net::Postgres;

my $client = await Net::Postgres::Connection.connect(:$host, :$port, :$user, :$password, :$database, :$tls);

my $resultset = await $client.query('SELECT * FROM foo WHERE id = $1', 42);
for $resultset.objects(Foo) -> $foo {
    do-something($foo);
}
await $client.transaction: {
    my $id = await $client.query('INSERT INTO foo(data) VALUES($1) RETURNING id', $data);
}
```

Description
===========

Net::Postgres is asynchronous implementation of (the client side of) the postgresql protocol based on `Protocol::Postgres`. It is typically used through the `Net::Postgres::Connection` class.

Client
======

`Net::Postgres::Client` has the following methods

connect-tcp(--> Promise)
------------------------

This creates a promise to a new postgres client. It takes the following named arguments:

  * Str :$host = 'localhost'

  * Int :$port = 5432

  * Str :$user = ~$*USER

  * Str :password

  * Str :$database

  * TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

  * Bool :$tls = False

  * :%tls-args = ()

connect-local(--> Promise)
--------------------------

  * IO(Str) :$path = '/var/run/postgresql/'.IO

  * Int :$port = 5432

  * Str :$user = ~$*USER

  * Str :password

  * Str :$database

  * TypeMap :$typemap = Protocol::Postgres::TypeMap::JSON

connect(--> Promise)
--------------------

This takes the same arguments as `connect-local` and `connect-tcp`. It will call the former if the `$host` is localhost and the `$path` exists, otherwise it will call `connect-tcp`.

query($query, @bind-values --> Promise)
---------------------------------------

This will issue a query with the given bind values, and return a promise to the result.

For fetching queries such as `SELECT` the result in the promise will be a `ResultSet` object, for manipulation (e.g. `INSERT`) and definition (e.g. `CREATE`) queries it will result a string describing the change (e.g. `DELETE 3`). For a `COPY TO` query it will `Supply` with the data stream, and for `COPY FROM` it will be a `Supplier`.

Both the input types and the output types will be typemapped between Raku types and Postgres types using the typemapper.

Not that this uses postgres-native placeholders (`$1, $2`), instead of DBI-style (`?, ?`).

query-multiple($query --> Supply[ResultSet])
--------------------------------------------

This will issue a complex query that may contain multiple statements, but can not use bind values. It will return a `Supply` to the results of each query.

prepare($query --> Promise[PreparedStatement])
----------------------------------------------

This prepares the query, and returns a Promise to the PreparedStatement object.

transaction(&code)
------------------

To use a transaction, one can use the `transaction` method. It's code reference will act as a wrapper for the transaction. If anything throws an exception out of the callback (e.g. a failed query method), a rollback will be attempted.

add-enum-type(Str $name, ::Enum --> Promise)
--------------------------------------------

This looks up the `oid` of postgres enum `$name`, and adds an appriopriate `Type` object to the typemap to convert it from/to `Enum`.

add-composite-type(Str $name, ::Composite, Bool :$positional --> Promise)
-------------------------------------------------------------------------

This looks up the `oid` of the postgres composite type <$name>, and maps it to `Composite`; if `$positional` is set it will use positional constructor arguments, otherwise named ones are used.

add-custom-type(Str $name, ::Custom, &from-string?, &to-string?)
----------------------------------------------------------------

This adds a custom converter from postgres type `$name` from/to Raku type `Custom`. By default `&from-string` will do a coercion, and `&to-string` will do stringification.

terminate(--> Nil)
------------------

This sends a message to the server to terminate the connection

listen(Str $channel-name --> Promise[Supply])
---------------------------------------------

This listens to notifications on the given channel. It returns a `Promise` to a `Supply` of `Notification`s.

query-status(--> Protocol::Postgres::QueryStatus)
-------------------------------------------------

This returns the query status as of the last finished query as a `enum Protocol::Postgres::QueryStatus` value: `Idle` (No transaction is active), `Transaction` (A transaction is currently in progress) or `Error` (The current transaction has failed and needs to be rolled back).

ResultSet
=========

A `Net::Postgres::ResultSet` represents the results of a query, if any. It defines the following methods:

columns(--> List)
-----------------

This returns the column names for this resultset.

rows(--> Supply[List])
----------------------

This returns a Supply of rows. Each row is a list of values.

hash-rows(--> Supply[Hash])
---------------------------

This returns a Supply of rows. Each row is a hash with the column names as keys and the row values as values.

object-rows(::Class, Bool :$positional --> Supply[Class])
---------------------------------------------------------

This returns a Supply of objects of class `Class`, each object is constructed form the row hash unless positional is true in which case it's constructed from the row list.

arrays
------

This returns a sequence of arrays of results from all rows. This may `await`.

array
-----

This returns a single array of results from one row. This may `await`.

value
-----

This returns a single value from a single row. This may `await`.

hashes
------

This returns a sequence of hashes of the results from all rows. This may `await`.

hash
----

This returns a single hash of the results from one rows. This may `await`.

objects(::Class, Bool :$positional)
-----------------------------------

This returns a sequence of objects based on all the rows. This may `await`.

object(:Class, Bool :$positional)
---------------------------------

This returns a single object based on a single row. This may `await`.

PreparedStatement
=================

A `Net::Postgres::PreparedStatement` represents a prepated statement. Its reason of existence is to call `execute` on it.

execute(@arguments --> Promise)
-------------------------------

This runs the prepared statement, much like the `query` method would have done and with the same result values.

close()
-------

This closes the prepared statement.

columns()
---------

This returns the columns of the result once executed.

Notification
============

`Net::Postgres::Notification` has the following methods:

message(--> Str)
----------------

This is the message of the notification. The notification will also stringify to this value.

channel(--> Str)
----------------

The channel of the notification.

sender(--> Int)
---------------

This is the process-id of the sender

Todo
====

  * Persistent connections

  * Connection pooling

Author
======

Leon Timmermans <fawaka@gmail.com>

Copyright and License
=====================

Copyright 2022 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.


use v6.d;

unit module Net::Postgres:ver<0.0.1>:auth<cpan:LEONT>;

use Protocol::Postgres;

class ResultSet is Protocol::Postgres::ResultSet {
	method arrays() { self.rows.list }
	method array()  { self.arrays.head }

	method value()  { self.array.head }

	method hashes() { self.hash-rows.list }
	method hash()   { self.hashes.head }
}

class PreparedStatement is Protocol::Postgres::PreparedStatement {
	method resultset() { ResultSet }
}

class Notification {
	has Int:D $.sender is required;
	has Str:D $.message is required handles<Str>;
}

my class Notification::Multiplexer {
	has Supplier %!channels;
	method submit(Protocol::Postgres::Notification $ (:$sender, :$channel, :$message --> Nil)) {
		if %!channels{$channel} -> $channel {
			$channel.emit(Notification.new(:$sender, :$message));
		}
	}
	method done() {
		for %!channels.values -> $channel {
			$channel.done;
		}
	}
	method get(Str $name --> Supply) {
		my $supplier = %!channels{$name} //= Supplier::Preserving.new;
		$supplier.Supply;
	}
}

class Connection {
	has Any:D $!socket is required is built;
	has Protocol::Postgres::Client:D $!client is required is built handles<disconnected terminate get-parameter process-id>;
	has Notification::Multiplexer $!multiplexer is built;

	method !connect(:$socket, :$user, :$database, :$password, :$typemap --> Connection) {
		my $client = Protocol::Postgres::Client.new(:$typemap);
		my $vow = $client.disconnected.vow;
		$socket.Supply(:bin).act({ $client.incoming-data($^data) }, :done{ $vow.keep(True) }, :quit{ $vow.break($^reason) });
		$client.outbound-data.act({ await $socket.write($^data) }, :done{ $socket.close });

		my $multiplexer = Notification::Multiplexer.new;
		$client.notifications.act({ $multiplexer.submit($^notification) }, :done{ $multiplexer.done }, :quit{ $multiplexer.done });

		await $client.startup($user, $database, $password);

		self.bless(:$socket, :$client, :$multiplexer);
	}

	method connect-tcp(Str :$host = 'localhost', Int :$port = 5432, Str :$user = ~$*USER, Str :$database, Str :$password, Protocol::Postgres::TypeMap :$typemap = Protocol::Postgres::TypeMap::Simple, Bool :$tls, *%tls-args --> Promise) {
		IO::Socket::Async.connect($host, $port).then: -> $promise {
			my $socket = await $promise;

			if ($tls) {
				require IO::Socket::Async::SSL;
				my $class = ::('IO::Socket::Async::SSL');
				die Protocol::Postgres::X::Client.new('Could not load IO::Socket::Async::SSL') if $class === Any;
				await $socket.write(Protocol::Postgres::Client.startTls);
				my $wanted = await $socket.Supply(:bin).head;
				die Protocol::Postgres::X::Client.new('TLS rejected') if $wanted ne Blob.new(0x53);
				$socket = await $class.upgrade-client($socket, :$host, |%tls-args);
			}

			self!connect(:$socket, :$user, :$database, :$password, :$typemap);
		}
	}
	method new() {
		die "You probably want to use connect-tcp instead";
	}

	method query(|args --> Promise) {
		$!client.query(|args, :resultset(ResultSet));
	}
	method query-multiple(|args --> Supply) {
		$!client.query-multiple(|args, :resultset(ResultSet));
	}
	method prepare(|args --> Promise) {
		$!client.prepare(|args, :prepared-statement(PreparedStatement));
	}

	method listen(Str $channel-name --> Promise) {
		my $supply = $!multiplexer.get($channel-name);
		my $query = $!client.query("LISTEN $channel-name");
		$query.then: { await $query; $supply };
	}
}

=begin pod

=head1 Name

Net::Postgres - an asynchronous postgresql client

=head1 Synopsis

=begin code :lang<raku>

use v6.d;
use Net::Postgres;

my $client = await Net::Postgres::Connection.connect-tcp(:$host, :$port, :$user, :$password, :$database, :$tls);

my $resultset = await $client.query('SELECT * FROM foo WHERE id = $1', 42);
for $resultset.hashes -> (:$name, :$description) {
    say "$name is $description";
}

=end code

=head1 Description

Net::Postgres is asynchronous implementation of (the client side of) the postgresql protocol based on C<Protocol::Postgres>. It is typically used through the C<Net::Postgres::Client> class.

=head1 Client

C<Net::Postgres::Client> has the following methods

=head2 new(--> Protocol::Postgres::Client)

This creates a new postgres client. It takes the following named arguments:

=item2 Str :$host = 'localhost'

=item2 Int :$port = 5432

=item2 Str :$user = ~$*USER

=item2 Str :password

=item2 Str :$database

=item2 TypeMap :$typemap = Protocol::Postgres::TypeMap::Simple

=item2 Bool :$tls = False

if C<$tls> is enabled, it will pass on all unknown named arguments to C<IO::Socket::Async::SSL>.

=head2 query($query, @bind-values --> Promise)

This will issue a query with the given bind values, and return a promise to the result.

For fetching queries such as C<SELECT> the result in the promise will be a C<ResultSet> object, for manipulation (e.g. C<INSERT>) and definition (e.g. C<CREATE>) queries it will result a string describing the change (e.g. C<DELETE 3>). For a C<COPY TO> query it will C<Supply> with the data stream, and for C<COPY FROM> it will be a C<Supplier>.

Both the input types and the output types will be typemapped between Raku types and Postgres types using the typemapper.

=head2 query-multiple($query --> Supply[ResultSet])

This will issue a complex query that may contain multiple statements, but can not use bind values. It will return a C<Supply> to the results of each query.

=head2 prepare($query --> Promise[PreparedStatement])

This prepares the query, and returns a Promise to the PreparedStatement object.

=head2 terminate(--> Nil)

This sends a message to the server to terminate the connection

=head2 listen(Str $channel-name --> Promise[Supply])

This listens to notifications on the given channel. It returns a C<Promise> to a C<Supply> of C<Notification>s.

=head1 ResultSet

A C<Net::Postgres::ResultSet> represents the results of a query, if any. It defines the following methods:

=head2 columns(--> List)

This returns the column names for this resultset.

=head2 rows(--> Supply[List])

This returns a Supply of rows. Each row is a list of values.

=head2 hash-rows(--> Supply[Hash])

This returns a Supply of rows. Each row is a hash with the column names as keys and the row values as values.

=head2 arrays

This returns a sequence of arrays of results from all rows. This may C<await>.

=head2 array

This returns a single array of results from one row. This may C<await>.

=head2 value

This returns a single value from a single row. This may C<await>.

=head2 hashes

This returns a sequence of hashes of the results from all rows. This may C<await>.

=head2 hash

This returns a single hash of the results from one rows. This may C<await>.

=head1 PreparedStatement

A C<Net::Postgres::PreparedStatement> represents a prepated statement. Its reason of existence is to call C<execute> on it.

=head2 execute(@arguments --> Promise)

This runs the prepared statement, much like the C<query> method would have done and with the same result values.

=head2 close()

This closes the prepared statement.

=head2 columns()

This returns the columns of the result once executed.

=head1 Notification

C<Net::Postgres::Notification> has the following methods:

=head2 sender(--> Int)

This is the process-id of the sender

=head2 message(--> Str)

This is the message of the notification

=head1 Todo

=item1 Persistent connections

=item1 Connection pooling

=head1 Author

Leon Timmermans <fawaka@gmail.com>

=head1 Copyright and License

Copyright 2022 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

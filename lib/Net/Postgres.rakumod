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

class Connection {
	has IO::Socket::Async:D $!socket is required;
	has Protocol::Postgres::Client:D $!client is required handles<terminate notifications get-parameter process-id>;
	submethod BUILD(:$!socket, :$!client) {}

	method connect-tcp(:$host = 'localhost', :$port = 5432, :$user = ~$*USER, :$database, :$password, :$typemap = TypeMap::Simple, :$tls, *%tls-args) {
		IO::Socket::Async.connect($host, $port).then: -> $promise {
			my $socket = await $promise;
			if ($tls) {
				die if $tls ~~ Protocol::Postgres::X::Client;
				require IO::Socket::Async::SSL;
				my $class = ::('IO::Socket::Async::SSL');
				die Protocol::Postgres::X::Client.new('Could not load IO::Socket::Async::SSL') if $class === Any;
				await $socket.write(Protocol::Postgres::Client.startTls);
				my $wanted = await $socket.Supply(:bin).head;
				dd Protocol::Postgres::X::Client.WHO;
				die Protocol::Postgres::X::Client.new('TLS rejected') if $wanted ne Blob.new(0x53);
				$socket = await $class.upgrade-client($socket, :$host, %tls-args);
			}

			my $disconnected = Promise.new;
			my $client  = Protocol::Postgres::Client.new(:$typemap, :$disconnected);
			$socket.Supply(:bin).act({ $client.incoming-data($^data) }, :done({ $disconnected.keep }), :quit({ $disconnected.break($^reason) }));
			$client.outbound-data.act({ await $socket.write($^data) }, :done({ $socket.close }));

			await $client.startup($user, $database, $password);

			self.bless(:$socket, :$client);
		}
	}
	method new() {
		die "You probably want to use connect-tcp instead";
	}

	method disconnected {
		$!client.disconnected.then({ await $^result });
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
}

=begin pod

=head1 Name

Net::Postgres - an asynchronous postgresql client

=head1 Synopsis

=begin code :lang<raku>

use v6.d;
use Protocol::Postgres;

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

For fetching queries such as C<SELECT> the result will be a C<ResultSet> object, for manipulation (e.g. C<INSERT>) and definition (e.g. C<CREATE>) queries it will result in the value C<True>.

Both the input types and the output types will be typemapped between Raku types and Postgres types using the typemapper.

=head2 query-multiple($query --> Supply[ResultSet])

This will issue a complex query that may contain multiple statements, but can not use bind values. It will return a C<Supply> to the results of each query.

=head2 prepare($query --> Promise[PreparedStatement])

This prepares the query, and returns a Promise to the PreparedStatement object.

=head2 terminate(--> Nil)

This sends a message to the server to terminate the connection

=head2 notifications(--> Supply[Notification])

This returns a supply with all notifications that the current connection is subscribed to. Channels can be subscribed using the C<LISTEN> command, and messages can be sent using the C<NOTIFY> command.

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

=head1 Notification

C<Protocol::Postgres::Notification> has the following methods:

=head2 sender(--> Int)

This is the process-id of the sender

=head2 channel(--> Str)

This is the name of the channel that the notification was sent on

=head2 payload(--> Str)

This is the payload of the notification

=head1 Todo

=item1 Implement connection pooling

=head1 Author

Leon Timmermans <fawaka@gmail.com>

=head1 Copyright and License

Copyright 2022 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

defmodule Instream.WriterTest do
  use ExUnit.Case, async: true

  alias Instream.TestHelpers.Connection
  alias Instream.TestHelpers.UDPConnection


  defmodule BatchSeries do
    use Instream.Series

    series do
      database    "test_database"
      measurement "location"

      tag :scope

      field :value
    end
  end

  defmodule EmptyTagSeries do
    use Instream.Series

    series do
      database    "test_database"
      measurement "empty_tags"

      tag :filled
      tag :defaulting, default: "default_value"
      tag :empty

      field :value
    end
  end

  defmodule ErrorsSeries do
    use Instream.Series

    series do
      database    "test_database"
      measurement "writer_errors"

      field :binary
    end
  end

  defmodule LineEncodingSeries do
    use Instream.Series

    series do
      database    "test_database"
      measurement "writer_line_encoding"

      field :binary
      field :boolean
      field :float
      field :integer
    end
  end

  defmodule CustomDatabaseSeries do
    use Instream.Series

    series do
      database    "invalid_test_database"
      measurement "writer_database_option"

      field :value
    end
  end

  defmodule ProtocolsSeries do
    use Instream.Series

    series do
      database    "test_database"
      measurement "writer_protocols"

      tag :bar
      tag :foo

      field :value
    end
  end


  test "writer protocols" do
    data = %ProtocolsSeries{}
    data = %{ data | tags: %{ data.tags | foo: "foo", bar: "bar" }}

    # Line (default) protocol
    data = %{ data | fields:    %{ data.fields | value: "Line" }}
    data = %{ data | timestamp: 1439587926 }

    assert :ok == data |> Connection.write(precision: :second)

    # UDP protocol
    data = %{ data | fields:    %{ data.fields | value: "UDP" }}
    data = %{ data | timestamp: 1439587927000000000 }

    assert :ok == data |> UDPConnection.write()

    # wait to ensure data was written
    :timer.sleep(1250)

    # check data
    result =
         "SELECT * FROM #{ ProtocolsSeries.__meta__(:measurement) } GROUP BY *"
      |> Connection.query([ database:  ProtocolsSeries.__meta__(:database),
                            precision: :nanosecond ])

    assert %{ results: [%{ series: [%{
      values: [
        [ 1439587926000000000, "Line" ],
        [ 1439587927000000000, "UDP" ]
      ]
    }]}]} = result
  end


  test "line protocol data encoding" do
    data = %LineEncodingSeries{}
    data = %{ data | fields: %{ data.fields | binary:  "binary",
                                              boolean: false,
                                              float:   1.1,
                                              integer: 100 }}

    assert :ok == data |> Connection.write()

    # wait to ensure data was written
    :timer.sleep(250)

    # check data
    result =
         "SELECT * FROM #{ LineEncodingSeries.__meta__(:measurement) } GROUP BY *"
      |> Connection.query(database: LineEncodingSeries.__meta__(:database))

    assert %{ results: [%{ series: [%{
      values: [[ _, "binary", false, 1.1, 100 ]]
    }]}]} = result
  end


  test "protocol error decoding" do
    data = %ErrorsSeries{}
    data = %{ data | fields: %{ data.fields | binary:  "binary" }}

    assert :ok = data |> Connection.write()

    # wait to ensure data was written
    :timer.sleep(250)

    # make entry fail
    data = %{ data | fields: %{ data.fields | binary: 12345 }}

    # Line protocol write error
    %{ error: error } = data |> Connection.write()

    String.contains?(error, "conflict")
  end


  test "line protocol batch series" do
    inside = %BatchSeries{}
    inside = %{ inside | tags: %{ inside.tags | scope: "inside" }}

    inside = %{ inside | fields:    %{ inside.fields | value: 1.23456 }}
    inside = %{ inside | timestamp: 1439587926 }

    outside = %BatchSeries{}
    outside = %{ outside | tags: %{ outside.tags | scope: "outside" }}

    outside = %{ outside | fields:    %{ outside.fields | value: 9.87654 }}
    outside = %{ outside | timestamp: 1439587927 }

    assert :ok == [ inside, outside ] |> Connection.write(precision: :second)

    # wait to ensure data was written
    :timer.sleep(250)

    # check data
    result =
         "SELECT * FROM #{ BatchSeries.__meta__(:measurement) }"
      |> Connection.query(database: BatchSeries.__meta__(:database))

    assert %{ results: [%{ series: [%{
      columns: [ "time", "scope", "value" ],
      values:  [[ "2015-08-14T21:32:06Z", "inside",  1.23456 ],
                [ "2015-08-14T21:32:07Z", "outside", 9.87654 ]]
    }]}]} = result
  end


  test "writing without all tags present" do
    entry = %EmptyTagSeries{}
    entry = %{ entry | tags:   %{ entry.tags   | filled: "filled_tag" }}
    entry = %{ entry | fields: %{ entry.fields | value: 100 }}

    assert :ok = Connection.write(entry)

    # wait to ensure data was written
    :timer.sleep(250)

    # check data
    result =
         "SELECT * FROM #{ EmptyTagSeries.__meta__(:measurement) }"
      |> Connection.query(database: EmptyTagSeries.__meta__(:database))

    %{ results: [%{ series: [%{ columns: columns }]}]} = result

    assert Enum.member?(columns, "filled")
    assert Enum.member?(columns, "defaulting")
    assert Enum.member?(columns, "value")

    refute Enum.member?(columns, "empty")
  end


  test "writing with passed database option" do
    database = "test_database"

    entry = %CustomDatabaseSeries{}
    entry = %{ entry | fields: %{ entry.fields | value: 100 }}
    assert :ok = Connection.write(entry, database: database)

    # wait to ensure data was written
    :timer.sleep(250)

    # check data
    result =
         "SELECT * FROM #{ CustomDatabaseSeries.__meta__(:measurement) }"
      |> Connection.query(database: database)

    %{ results: [%{ series: [%{ columns: columns }]}]} = result

    assert Enum.member?(columns, "value")
  end
end

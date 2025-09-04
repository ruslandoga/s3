defmodule S3.XMLTest do
  use ExUnit.Case, async: true

  test "decodes lists correctly by merging values in a list" do
    input = """
    <person>
      <name>foo</name>
      <addresses>
        <address>1</address>
        <address>2</address>
        <address>œ</address>
      </addresses>
    </person>
    """

    assert S3.xml(input) ==
             %{
               "person" => %{
                 "name" => "foo",
                 "addresses" => %{
                   "address" => ["1", "2", "œ"]
                 }
               }
             }
  end

  test "ignores text elments mixed with other elements" do
    input = """
    <person>
      <name>foo</name>
      random
    </person>
    """

    assert S3.xml(input) == %{"person" => %{"name" => "foo"}}

    input = """
    <person>
      <name>foo</name>
      random
      <age>42</age>
      text
    </person>
    """

    assert S3.xml(input) == %{"person" => %{"name" => "foo", "age" => "42"}}
  end

  test "can encode" do
    input = %{
      "TagWithAttrs" => %{
        "TagWithOutAttrs" => %{
          "TestTypes" => [
            %{"BoolVal" => true},
            %{"IntVal" => 1},
            %{"FloatVal" => 1.0},
            %{"BinValue" => "hello"}
          ]
        }
      }
    }

    assert IO.iodata_to_binary(S3.xml(input)) == """
           <TagWithAttrs>\
           <TagWithOutAttrs>\
           <TestTypes><BoolVal>true</BoolVal></TestTypes>\
           <TestTypes><IntVal>1</IntVal></TestTypes>\
           <TestTypes><FloatVal>1.0</FloatVal></TestTypes>\
           <TestTypes><BinValue>hello</BinValue></TestTypes>\
           </TagWithOutAttrs>\
           </TagWithAttrs>\
           """
  end
end

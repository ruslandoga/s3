defmodule S3.XMLTest do
  use ExUnit.Case, async: true

  @text "__text"

  test "decodes lists correctly by merging values in a list" do
    _expected = %{"person" => %{"name" => "foo", "addresses" => %{"address" => ["1", "2", "œ"]}}}

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
             {:ok,
              {"person",
               [
                 {"name", ["foo"]},
                 {"addresses", [{"address", ["1"]}, {"address", ["2"]}, {"address", ["œ"]}]}
               ]}}
  end

  test "decodes multiple text elments mixed with other elements correctly" do
    _expected = %{"person" => %{"name" => "foo", @text => "random"}}

    input = """
    <person>
      <name>foo</name>
      random
    </person>
    """

    assert S3.xml(input) == {:ok, {"person", [{"name", ["foo"]}, "\n  random\n"]}}

    _expected = %{"person" => %{"name" => "foo", "age" => "42", @text => "random\n  \n  text"}}

    input = """
    <person>
      <name>foo</name>
      random
      <age>42</age>
      text
    </person>
    """

    assert S3.xml(input) ==
             {:ok,
              {"person", [{"name", ["foo"]}, "\n  random\n  ", {"age", ["42"]}, "\n  text\n"]}}
  end

  test "encodes all possible types" do
    _input = %{
      {"TagWithAttrs", %{xmlns: "some-ns"}} => %{
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

    input =
      {"TagWithAttrs",
       [
         {"TagWithOutAttrs",
          [
            {"TestTypes", [{"BoolVal", [true]}]},
            {"TestTypes", [{"IntVal", [1]}]},
            {"TestTypes", [{"FloatVal", [1.0]}]},
            {"TestTypes", [{"BinValue", ["hello"]}]}
          ]}
       ]}

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

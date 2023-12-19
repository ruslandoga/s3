defmodule S3Test do
  use ExUnit.Case, async: true

  @config [
    access_key_id: "AKIAZZM67ULNV4CSXW4B",
    secret_access_key: "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",
    url: URI.parse("https://vl3tueq.s3.ap-southeast-1.amazonaws.com"),
    region: "ap-southeast-1",
    utc_now: ~U[2023-12-13 11:22:36.220710Z]
  ]

  test "simple HeadObject" do
    {uri, headers, body} =
      S3.build([method: :head, path: "Screenshot 2023-11-27 at 20.39.07.png"] ++ @config)

    assert uri == %URI{
             scheme: "https",
             authority: "vl3tueq.s3.ap-southeast-1.amazonaws.com",
             userinfo: nil,
             host: "vl3tueq.s3.ap-southeast-1.amazonaws.com",
             port: 443,
             path: "/Screenshot%202023-11-27%20at%2020.39.07.png",
             query: "",
             fragment: nil
           }

    assert headers == [
             {
               "authorization",
               """
               AWS4-HMAC-SHA256 Credential=AKIAZZM67ULNV4CSXW4B/20231213/ap-southeast-1/s3/aws4_request,\
               SignedHeaders=host;x-amz-content-sha256;x-amz-date,\
               Signature=7b56d04749225531bdf4a754152323b99e1b028b4867933f2064b2d88b86d0e2\
               """
             },
             {"host", "vl3tueq.s3.ap-southeast-1.amazonaws.com"},
             {"x-amz-content-sha256",
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
             {"x-amz-date", "20231213T112236Z"}
           ]

    assert body == []
  end

  # TODO test unicode
  test "xml/1" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Name>testbucket</Name>
      <Prefix></Prefix>
      <KeyCount>2</KeyCount>
      <MaxKeys>1000</MaxKeys>
      <IsTruncated>false</IsTruncated>
      <Contents>
        <Key>my-bytes-1702544080-292</Key>
        <LastModified>2023-12-14T08:54:40.085Z</LastModified>
        <ETag>&#34;879f4bba57ed37c9ec5e5aedf9864698&#34;</ETag>
        <Size>1000000</Size>
        <StorageClass>STANDARD</StorageClass>
      </Contents>
      <Contents>
        <Key>my-bytes-1702544080-66</Key>
        <LastModified>2023-12-14T08:54:40.042Z</LastModified>
        <ETag>&#34;879f4bba57ed37c9ec5e5aedf9864698&#34;</ETag>
        <Size>1000000</Size>
        <StorageClass>STANDARD</StorageClass>
      </Contents>
    </ListBucketResult>\
    """

    assert {:ok, xml} = S3.xml(xml)

    assert xml ==
             {"ListBucketResult",
              [
                {"Name", ["testbucket"]},
                {"Prefix", []},
                {"KeyCount", ["2"]},
                {"MaxKeys", ["1000"]},
                {"IsTruncated", ["false"]},
                {"Contents",
                 [
                   {"Key", ["my-bytes-1702544080-292"]},
                   {"LastModified", ["2023-12-14T08:54:40.085Z"]},
                   {"ETag", ["\"879f4bba57ed37c9ec5e5aedf9864698\""]},
                   {"Size", ["1000000"]},
                   {"StorageClass", ["STANDARD"]}
                 ]},
                {"Contents",
                 [
                   {"Key", ["my-bytes-1702544080-66"]},
                   {"LastModified", ["2023-12-14T08:54:40.042Z"]},
                   {"ETag", ["\"879f4bba57ed37c9ec5e5aedf9864698\""]},
                   {"Size", ["1000000"]},
                   {"StorageClass", ["STANDARD"]}
                 ]}
              ]}

    # TODO
    # assert xml ==
    #          %{
    #            "ListBucketResult" => %{
    #              "Name" => "testbucket",
    #              "KeyCount" => "2",
    #              "MaxKeys" => "1000",
    #              "IsTruncated" => "false",
    #              "Contents" => [
    #                %{
    #                  "Key" => "my-bytes-1702544080-292",
    #                  "LastModified" => "2023-12-14T08:54:40.085Z",
    #                  "ETag" => "\"879f4bba57ed37c9ec5e5aedf9864698\"",
    #                  "Size" => "1000000",
    #                  "StorageClass" => "STANDARD"
    #                },
    #                %{
    #                  "Key" => "my-bytes-1702544080-66",
    #                  "LastModified" => "2023-12-14T08:54:40.042Z",
    #                  "ETag" => "\"879f4bba57ed37c9ec5e5aedf9864698\"",
    #                  "Size" => "1000000",
    #                  "StorageClass" => "STANDARD"
    #                }
    #              ]
    #            }
    #          }
  end

  # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
  test "sigv4 streaming" do
    assert {%URI{} = uri, headers, {:stream, signed_stream}} =
             S3.build(
               access_key_id: "AKIAIOSFODNN7EXAMPLE",
               secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
               url: "https://s3.amazonaws.com",
               path: "/examplebucket/chunkObject.txt",
               region: "us-east-1",
               method: :put,
               headers: [
                 {"content-length", "66824"},
                 {"content-encoding", "aws-chunked"},
                 {"x-amz-storage-class", "REDUCED_REDUNDANCY"},
                 {"x-amz-decoded-content-length", "66560"}
               ],
               utc_now: ~U[2013-05-24 00:00:00Z],
               body:
                 {:stream,
                  Stream.map([65536, 1024, 0], fn size -> String.duplicate("a", size) end)}
             )

    assert uri.scheme == "https"
    assert uri.host == "s3.amazonaws.com"
    assert uri.path == "/examplebucket/chunkObject.txt"

    expected_authorization =
      """
      AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,\
      SignedHeaders=content-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-storage-class,\
      Signature=4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9\
      """

    assert headers == [
             {"authorization", expected_authorization},
             {"content-encoding", "aws-chunked"},
             {"content-length", "66824"},
             {"host", "s3.amazonaws.com"},
             {"x-amz-content-sha256", "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"},
             {"x-amz-date", "20130524T000000Z"},
             {"x-amz-decoded-content-length", "66560"},
             {"x-amz-storage-class", "REDUCED_REDUNDANCY"}
           ]

    signed_chunks = Enum.map(signed_stream, &IO.iodata_to_binary/1)
    assert IO.iodata_length(signed_chunks) == 66824

    assert signed_chunks == [
             "10000;chunk-signature=ad80c730a21e5b8d04586a2213dd63b9a0e99e0e2307b0ade35a65485a288648\r\n" <>
               String.duplicate("a", 65536) <> "\r\n",
             "400;chunk-signature=0055627c9e194cb4542bae2aa5492e3c1575bbb81b612b7d234b86a503ef5497\r\n" <>
               String.duplicate("a", 1024) <> "\r\n",
             "0;chunk-signature=b6c6ea8a5354eaf15b3cb7646744f4275b71ea724fed81ceb9323e279d449df9\r\n\r\n"
           ]
  end
end

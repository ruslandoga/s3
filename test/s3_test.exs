defmodule S3Test do
  use ExUnit.Case, async: true
  doctest S3, import: true

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

    assert {:ok, decoded} = S3.xml(xml)

    assert decoded ==
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

    encoded = IO.iodata_to_binary(S3.xml(decoded))

    assert encoded == """
           <ListBucketResult>\
           <Name>testbucket</Name>\
           <Prefix></Prefix>\
           <KeyCount>2</KeyCount>\
           <MaxKeys>1000</MaxKeys>\
           <IsTruncated>false</IsTruncated>\
           <Contents>\
           <Key>my-bytes-1702544080-292</Key>\
           <LastModified>2023-12-14T08:54:40.085Z</LastModified>\
           <ETag>\"879f4bba57ed37c9ec5e5aedf9864698\"</ETag>\
           <Size>1000000</Size>\
           <StorageClass>STANDARD</StorageClass>\
           </Contents>\
           <Contents>\
           <Key>my-bytes-1702544080-66</Key>\
           <LastModified>2023-12-14T08:54:40.042Z</LastModified>\
           <ETag>\"879f4bba57ed37c9ec5e5aedf9864698\"</ETag>\
           <Size>1000000</Size>\
           <StorageClass>STANDARD</StorageClass>\
           </Contents>\
           </ListBucketResult>\
           """

    assert {:ok, decoded} == S3.xml(encoded)

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

  # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-post-example.html
  test "signed upload form" do
    # policy
    # { "expiration": "2015-12-30T12:00:00.000Z",
    #   "conditions": [
    #     {"bucket": "sigv4examplebucket"},
    #     ["starts-with", "$key", "user/user1/"],
    #     {"acl": "public-read"},
    #     {"success_action_redirect": "http://sigv4examplebucket.s3.amazonaws.com/successful_upload.html"},
    #     ["starts-with", "$Content-Type", "image/"],
    #     {"x-amz-meta-uuid": "14365123651274"},
    #     {"x-amz-server-side-encryption": "AES256"},
    #     ["starts-with", "$x-amz-meta-tag", ""],

    #     {"x-amz-credential": "AKIAIOSFODNN7EXAMPLE/20151229/us-east-1/s3/aws4_request"},
    #     {"x-amz-algorithm": "AWS4-HMAC-SHA256"},
    #     {"x-amz-date": "20151229T000000Z" }
    #   ]
    # }

    # copied from the aws example
    encoded_policy =
      "eyAiZXhwaXJhdGlvbiI6ICIyMDE1LTEyLTMwVDEyOjAwOjAwLjAwMFoiLA0KICAiY29uZGl0aW9ucyI6IFsNCiAgICB7ImJ1Y2tldCI6ICJzaWd2NGV4YW1wbGVidWNrZXQifSwNCiAgICBbInN0YXJ0cy13aXRoIiwgIiRrZXkiLCAidXNlci91c2VyMS8iXSwNCiAgICB7ImFjbCI6ICJwdWJsaWMtcmVhZCJ9LA0KICAgIHsic3VjY2Vzc19hY3Rpb25fcmVkaXJlY3QiOiAiaHR0cDovL3NpZ3Y0ZXhhbXBsZWJ1Y2tldC5zMy5hbWF6b25hd3MuY29tL3N1Y2Nlc3NmdWxfdXBsb2FkLmh0bWwifSwNCiAgICBbInN0YXJ0cy13aXRoIiwgIiRDb250ZW50LVR5cGUiLCAiaW1hZ2UvIl0sDQogICAgeyJ4LWFtei1tZXRhLXV1aWQiOiAiMTQzNjUxMjM2NTEyNzQifSwNCiAgICB7IngtYW16LXNlcnZlci1zaWRlLWVuY3J5cHRpb24iOiAiQUVTMjU2In0sDQogICAgWyJzdGFydHMtd2l0aCIsICIkeC1hbXotbWV0YS10YWciLCAiIl0sDQoNCiAgICB7IngtYW16LWNyZWRlbnRpYWwiOiAiQUtJQUlPU0ZPRE5ON0VYQU1QTEUvMjAxNTEyMjkvdXMtZWFzdC0xL3MzL2F3czRfcmVxdWVzdCJ9LA0KICAgIHsieC1hbXotYWxnb3JpdGhtIjogIkFXUzQtSE1BQy1TSEEyNTYifSwNCiAgICB7IngtYW16LWRhdGUiOiAiMjAxNTEyMjlUMDAwMDAwWiIgfQ0KICBdDQp9"

    options = [
      region: "us-east-1",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      utc_now: ~U[2015-12-29 00:00:00Z],
      body: encoded_policy
    ]

    assert S3.signature(options) ==
             "8afdbf4008c03f22c2cd3cdb72e4afbb1f6a588f3255ac628749a66d7f09699e"
  end

  @tag :skip
  test "signed upload form (jason)" do
    access_key_id = "AKIAIOSFODNN7EXAMPLE"
    secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    region = "us-east-1"
    utc_now = DateTime.utc_now()

    bucket = "sigv4examplebucket"
    acl = "public-read"
    success_action_redirect = "http://#{bucket}.s3.amazonaws.com/successful_upload.html"

    amz_meta_uuid = "14365123651274"
    amz_short_date = Calendar.strftime(utc_now, "%Y%m%d")
    amz_date = Calendar.strftime(utc_now, "%Y%m%dT%H%M%SZ")
    amz_credential = "#{access_key_id}/#{amz_short_date}/#{region}/s3/aws4_request"

    checks = [
      ["starts-with", "$key", "user/user1/"],
      ["starts-with", "$Content-Type", "image/"],
      ["starts-with", "$x-amz-meta-tag", ""]
    ]

    policy =
      Jason.encode_to_iodata!(%{
        "expiration" => DateTime.add(utc_now, :timer.hours(36), :millisecond),
        "conditions" =>
          [
            %{"bucket" => bucket},
            %{"acl" => acl},
            %{"success_action_redirect" => success_action_redirect},
            %{"x-amz-meta-uuid" => amz_meta_uuid},
            %{"x-amz-server-side-encryption" => "AES256"},
            %{"x-amz-credential" => amz_credential},
            %{"x-amz-algorithm" => "AWS4-HMAC-SHA256"},
            %{"x-amz-date" => amz_date}
          ] ++ checks
      })

    encoded_policy = Base.encode16(policy, case: :lower)

    _signature =
      S3.signature(
        secret_access_key: secret_access_key,
        utc_now: utc_now,
        body: encoded_policy,
        region: region
      )

    # <form action="http://sigv4examplebucket.s3.amazonaws.com/" method="post" enctype="multipart/form-data">
    #   Key to upload:
    #   <input type="input"  name="key" value="user/user1/${filename}" /><br />
    #   <input type="hidden" name="acl" value="public-read" />
    #   <input type="hidden" name="success_action_redirect" value="http://sigv4examplebucket.s3.amazonaws.com/successful_upload.html" />
    #   Content-Type:
    #   <input type="input"  name="Content-Type" value="image/jpeg" /><br />
    #   <input type="hidden" name="x-amz-meta-uuid" value="14365123651274" />
    #   <input type="hidden" name="x-amz-server-side-encryption" value="AES256" />
    #   <input type="text"   name="X-Amz-Credential" value="AKIAIOSFODNN7EXAMPLE/20151229/us-east-1/s3/aws4_request" />
    #   <input type="text"   name="X-Amz-Algorithm" value="AWS4-HMAC-SHA256" />
    #   <input type="text"   name="X-Amz-Date" value="20151229T000000Z" />

    #   Tags for File:
    #   <input type="input"  name="x-amz-meta-tag" value="" /><br />
    #   <input type="hidden" name="Policy" value='<Base64-encoded policy string>' />
    #   <input type="hidden" name="X-Amz-Signature" value="<signature-value>" />
    #   File:
    #   <input type="file"   name="file" /> <br />
    #   <!-- The elements after this will be ignored -->
    #   <input type="submit" name="submit" value="Upload to Amazon S3" />
    # </form>
  end

  # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
  test "signed url" do
    assert uri =
             S3.sign(
               access_key_id: "AKIAIOSFODNN7EXAMPLE",
               secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
               region: "us-east-1",
               method: :get,
               url: "https://examplebucket.s3.amazonaws.com",
               path: "/test.txt",
               query: %{"X-Amz-Expires" => 86400},
               utc_now: ~U[2013-05-24 00:00:00Z]
             )

    assert URI.to_string(uri) ==
             "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
  end
end

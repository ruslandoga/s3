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

  # TODO unicode
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

    assert S3.xml(xml) == [
             {
               "ListBucketResult",
               [
                 {"Name", "testbucket"},
                 {"Prefix", []},
                 {"KeyCount", "2"},
                 {"MaxKeys", "1000"},
                 {"IsTruncated", "false"},
                 {
                   "Contents",
                   [
                     {"Key", "my-bytes-1702544080-292"},
                     {"LastModified", "2023-12-14T08:54:40.085Z"},
                     {"ETag", "\"879f4bba57ed37c9ec5e5aedf9864698\""},
                     {"Size", "1000000"},
                     {"StorageClass", "STANDARD"}
                   ]
                 },
                 {
                   "Contents",
                   [
                     {"Key", "my-bytes-1702544080-66"},
                     {"LastModified", "2023-12-14T08:54:40.042Z"},
                     {"ETag", "\"879f4bba57ed37c9ec5e5aedf9864698\""},
                     {"Size", "1000000"},
                     {"StorageClass", "STANDARD"}
                   ]
                 }
               ]
             }
           ]
  end
end

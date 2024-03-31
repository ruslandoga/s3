Benchee.run(
  %{
    "S3.xml/1" => &S3.xml/1,
    "SweetXml.parse/1" => &SweetXml.parse/1,
    "AWS.XML.decode!/1" => &AWS.XML.decode!/1,
    "Saxy.SimpleForm.parse_string/1" => &Saxy.SimpleForm.parse_string/1,
    "Meeseeks.parse/1" => &Meeseeks.parse/1
  },
  memory_time: 2,
  inputs: %{
    "ListBucketResult (small)" => """
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
  }
)

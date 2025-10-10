use tantivy::schema::{NumericOptions, Schema, SchemaBuilder, STORED, STRING, TEXT};

pub fn build_schema() -> Schema {
    let mut builder = SchemaBuilder::default();

    builder.add_text_field("path", STRING | STORED);
    builder.add_text_field("name", TEXT | STORED);
    builder.add_text_field("name_raw", STRING | STORED);
    builder.add_text_field("ext", STRING);
    builder.add_text_field("identity", STRING | STORED);

    let mtime = NumericOptions::default().set_stored().set_fast();
    builder.add_i64_field("mtime", mtime);

    let size = NumericOptions::default().set_stored().set_fast();
    builder.add_u64_field("size", size);

    let inode = NumericOptions::default().set_stored();
    builder.add_u64_field("inode", inode);

    let dev = NumericOptions::default().set_stored();
    builder.add_u64_field("dev", dev);

    builder.add_text_field("content", TEXT);

    builder.build()
}

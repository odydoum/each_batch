# EachBatch

Improved batch processing in Rails.

This gem provides a new method called `each_batch` to ActiveRecord relations, similar to the built-in `in_batches`.

There are two main issues this gem attempts to tackle:

- No custom ordering. Rails' default and only behaviour is to order the results by the primary key.
- No proper use of indexes, because of the inability to set custom ordering.
- No efficient pluck solution in batches.  

## Example

Suppose we have a huge products table:

```ruby
ActiveRecord::Schema.define(version: 1) do
  create_table :products do |t|
    t.datetime :enabled_at, index: true
    t.integer :sales

    t.timestamps
  end
end
```

And suppose we want to process a subset of the data based on the enabled_at value: In Rails, one can do this:

```ruby
Product.
  where(enabled_at: a_date_range).
  find_each { |product| product.do_something }
```

This would generate SQL similar to this:

```SQL
SELECT `products`.*
FROM `products`
WHERE `products`.`enabled_at` BETWEEN '2023-05-28 00:00:00' AND '2023-06-04 23:59:59'
ORDER BY `products`.`id` ASC LIMIT 1000
```

And for subsequent batches something like this:

```SQL
SELECT `products`.*
FROM `products`
WHERE `products`.`enabled_at` BETWEEN '2023-05-28 00:00:00' AND '2023-06-04 23:59:59'
AND `products`.`id` > 123456
ORDER BY `products`.`id` ASC LIMIT 1000
```

The order clause here is what can kill performance! It doesn't utilize the index properly because of that.

With this gem, one can write this instead:

```ruby
Product.
  where(enabled_at: a_date_range).
  each_batch(keys: [:enabled_at, :id]).
  each_record { |product| product.do_something }
```
Which would generate something like the following:

```SQL
SELECT `products`.*
FROM `products`
WHERE `products`.`enabled_at` BETWEEN '2023-05-28 00:00:00' AND '2023-06-04 23:59:59'
ORDER BY `products`.`enabled_at` ASC, `products`.`id` ASC LIMIT 1000
```

This order matches the index one and the index will be utilized properly.

For subsequent batches:

```SQL
SELECT `products`.*
FROM `products`
WHERE `products`.`enabled_at` BETWEEN '2023-05-28 00:00:00' AND '2023-06-04 23:59:59'
AND (`products`.`enabled_at`, `products`.`id`) > ('2023-05-29 00:00:00', 123456)
ORDER BY `products`.`enabled_at` ASC, `products`.`id` ASC LIMIT 1000
```

which again, utilizes the index properly.

Note: the generated query is not exactly like the above, see [where_row](https://github.com/odydoum/where_row) for more info.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'each_batch'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install each_batch

## Usage

### Iterating in batches

To simply iterate a relation in batches:

```ruby
Product.each_batch do |batch|
  # do something useful
end 
```

By default the batch size is 1000. To override, use the `of` option:

```ruby
Product.each_batch(of: 500) do |batch|
  # do something useful
end 
```

Naturally, any relation can be batched, like so:

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500) do |batch|
  # do something useful
end 
```

Assuming that `products` is a huge table with an index on `enabled_at`, it would make more sense to order the results by this date. And in order to have a deterministic order (many products could be updated on the same time), ordering by `enabled_at` and `id` could prove optimal. To do that, use the `keys` option:

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500, keys: [:enabled_at, :id]) do |batch|
  # do something useful
end 
```

To change the order, use the `order` option (by default is accending):

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500, order: :desc, keys: [:enabled_at, :id]) do |batch|
  # do something useful
end 
```

To access each record instead of the whole relation (this preloads the relation), use `each_record`:

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500, keys: [:enabled_at, :id]).each_record do |record|
  # do something useful
end 
```

### Plucking in batches

To simply iterate over pluck results in batches, use the `pluck` method:

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500, keys: [:enabled_at, :id]).pluck(:id, :enabled_at) do |pluck_batch|
  # do something useful
end 
```

To iterate over each row instead, use the `each_row` method:

```ruby
Product.where(enabled_at: a_date_range).each_batch(of: 500, keys: [:enabled_at, :id]).pluck(:id, :enabled_at).each_row do |(id, enabled_at)|
  # do something useful
end 
```

### Enumerator usage

Since these methods return an enumerator, they can be chained with regular enumerator methods:

```ruby
Product.
  where(enabled_at: a_date_range).
  each_batch(of: 500, keys: [:enabled_at, :id]).
  pluck(:id, :enabled_at, :sales).
  each_row.
  sum(&:first)
```

## Caveats

### Empty results

By default, `each_batch` does not preload any records, it just build the necessary queries and yields the relation. This means that it can not know in advance
whether there are any records for the specified conditions. In practice this means that it will **always** yield a relation, even if it's empty.

This also applies if the result set is a multiple of the batch size. There is no way to deduce that no more results are present, so it will return an empty relation.

`each_record`, `pluck` and `each_row` do not suffer from this since they preload the records/values necessary to deduce that.

### Missing keys for select or pluck

For the algorithm to work, we need the last values for each of the keys specified. This means that there must a exist a select clause with those columns:

```ruby
Product.each_batch(of: 500, keys: [:enabled_at, :id]) # ok
Product.select(:id, :sales).each_batch(of: 500, keys: [:enabled_at, :id]) # ArgumentError
Product.select(:id, :enabled_at, :sales).each_batch(of: 500, keys: [:enabled_at, :id]) # Ok

Product.each_batch(of: 500, keys: [:enabled_at, :id]).pluck # Ok, plucks everything
Product.each_batch(of: 500, keys: [:enabled_at, :id]).pluck(:id, :sales) # ArgumentError
Product.each_batch(of: 500, keys: [:enabled_at, :id]).pluck(:id, :enabled_at) # Ok
Product.each_batch(of: 500, keys: [:enabled_at, :id]).pluck(:enabled_at, :id) # Ok
```
### Can't omit primary key

To make this method safer, we can not specify an ordering that doesn't have the primary key as the last order key. This is in order to always guarantee deterministic ordering. This could be relaxed, possible with an extra option `unsafe`, to make it explicit.

### Race conditions

This is inherent to batch processing in general.

## Alternatives

[pluck_in_batches](https://github.com/fatkodima/pluck_in_batches)

[each_batched](https://github.com/dburry/each_batched)

I am probably missing a lot here..

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/odydoum/each_batch.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

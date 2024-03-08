# Setup

Based on the [post](https://eduanbekker.com/post/pg-partman/) from Eduan Bekker.

```bash
docker build -t partman .
docker run -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=postgres -d -p 5432:5432 --name partman partman
```

Connect to the DB and run this:

```sql
CREATE SCHEMA partman;
CREATE EXTENSION pg_partman WITH SCHEMA partman;
CREATE EXTENSION pg_cron;
```

## Sandbox

Now you can play around with pg_cron and pg_partman. If you would like to start clean, you can run:

```bash
docker stop partman
docker rm partman
docker run -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=postgres -d -p 5432:5432 --name partman partman
```

Let's start by creating a table called `sample`

```sql
CREATE SCHEMA sample;

CREATE TABLE sample.sample (
  id SERIAL,
  created_at TIMESTAMP NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);

CREATE INDEX ON sample.sample (created_at);
```

Let's create a template table, which will be used to create indexes or constraints on our partition tables. This is optional, and can be created for you by partman, however you would still need to manually alter the autogenerated table if needed.

```sql
CREATE TABLE sample.sample_template (LIKE sample.sample);
ALTER TABLE sample.sample_template ADD PRIMARY KEY (id);
```

And then partition it by minutes to make sure it works:

```sql
SELECT partman.create_parent(
  p_parent_table := 'sample.sample'
  , p_control := 'created_at'
  , p_interval := '1 minute'
  , p_template_table := 'sample.sample_template'
  , p_premake := 2
);
```

Now check how many partitions there are:

```sql
select count(*) from partman.show_partitions('sample.sample');
```

This should be more than 1. If not, play around with the `p_start_partition` and `p_premake`.

At this point, only the parent was created. We need to config it to create infinite partitions:

```sql
UPDATE partman.part_config SET
  infinite_time_partitions = TRUE
  , retention = NULL -- aka never delete old partitions
  , retention_keep_table = TRUE
WHERE
  parent_table = 'sample.sample';
```

### Maintenance

By default, when you insert data it will be routed to the correct partition automatically for you.

```sql
INSERT INTO sample.sample (created_at) VALUES 
  (CURRENT_TIMESTAMP)
  , (CURRENT_TIMESTAMP - INTERVAL '5 minutes')
  , (CURRENT_TIMESTAMP + INTERVAL '15 minutes')
  , (CURRENT_TIMESTAMP - INTERVAL '1 hour')
;
```

Note that when there are time points/partitions that have not yet been created, this data is then routed to the `sample.sample_default` table. This is a temporary location, which can later be adjusted during a maintenance step.

If you want to tell pg_partman to enforce its desired state:

```sql
CALL partman.run_maintenance_proc();
```

Or here is the magic, schedule it with pg_cron!

```sql
SELECT cron.schedule('* * * * *', $$CALL partman.run_maintenance_proc()$$);
```

Note that this maintenance function will try to create the `p_premake` number of partitions based on the current time point. With the data we inserted above there are two issues:

- There is data that is outside the range of our initial partition table creation (1 hour ago).
- There is also data that is blocking new partitions from being made because it breaks the PARTITION CONSTRAINT.

What we can do is run the maintenance function to move all data out of the default partition table and to the correct partitions:

```sql
CALL partman.partition_data_proc(p_parent_table := 'sample.sample');
-- NOTICE:  Ensure to VACUUM ANALYZE the parent after partitioning data
```

If you expect more old data to be inserted then it would be good to preemptively fill the gap in the partition tables that has now been created, which can be done with this script:

```sql
SELECT partman.partition_gap_fill(p_parent_table := 'sample.sample');
```

# Conclusion

For more reading you can check out the [how-to guide](https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman_howto.md) on pg_partman.
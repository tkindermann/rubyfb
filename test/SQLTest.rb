#!/usr/bin/env ruby

require './TestSetup'
require 'test/unit'
require 'rubygems'
require 'rubyfb'

include Rubyfb

class SQLTest < Test::Unit::TestCase
   DB_FILE     = File.join(DB_DIR, "sql_unit_test.fdb")
   ITERATIONS  = 100
   
   INSERT_SQL  = "INSERT INTO TEST_TABLE VALUES(?, ?, ?, ?, ?, ?)"
   
   def setup
      puts "#{self.class.name} started." if TEST_LOGGING
      if File::exist?(DB_FILE)
         Database.new(DB_FILE).drop(DB_USER_NAME, DB_PASSWORD)
      end
      @database     = Database::create(DB_FILE, DB_USER_NAME, DB_PASSWORD)
      @connections  = []
      @transactions = []
      
      @database.connect(DB_USER_NAME, DB_PASSWORD) do |cxn|
         cxn.execute_immediate('CREATE TABLE TEST_TABLE (TESTID INTEGER '\
                               'NOT NULL PRIMARY KEY, TESTTEXT VARCHAR(100), '\
                               'TESTFLOAT NUMERIC(8,2), TESTDATE DATE, TESTTIME '\
                               'TIME, TESTSTAMP TIMESTAMP)')
      end
   end
   
   def teardown
      @transactions.each do |tx|
         tx.rollback if tx.active?
      end
      
      @connections.each do |cxn|
         cxn.close if cxn.open?
      end
      
      if File::exist?(DB_FILE)
         Database.new(DB_FILE).drop(DB_USER_NAME, DB_PASSWORD)
      end
      puts "#{self.class.name} finished." if TEST_LOGGING
   end
   
   def test01
      @database.connect(DB_USER_NAME, DB_PASSWORD) do |cxn|
         cxn.start_transaction do |tx|
            s = cxn.create_statement(INSERT_SQL)
            f = 0.0
            t = Time.new
            
            1.upto(ITERATIONS) do |i|
               f += 0.321
               t = Time.at(t.to_i + 5)
               s.exec([i, i.to_s, f, t, nil, t], tx)
            end

            s.close
         end
      end
      
      @connections.push(@database.connect(DB_USER_NAME, DB_PASSWORD))
      @connections[0].start_transaction do |tx|
         r = tx.execute("SELECT COUNT(*) FROM TEST_TABLE")
         assert(r.fetch[0] == ITERATIONS)
         r.close
      end
   end
   
   def test02
      f = 0.0
      @database.connect(DB_USER_NAME, DB_PASSWORD) do |cxn|
         1.upto(20) do |i|
            f += i
            sql = "INSERT INTO TEST_TABLE VALUES (#{i}, "\
                  "#{f.to_s}, #{f}, NULL, NULL, 'NOW')"
            cxn.execute_immediate(sql)
         end
      end
      
      @connections.push(@database.connect(DB_USER_NAME, DB_PASSWORD))
      @transactions.push(@connections[0].start_transaction)
      r = @transactions[0].execute("SELECT COUNT(*) FROM TEST_TABLE")
      assert(r.fetch[0] == 20)
      r.close
      
      r = @transactions[0].execute("SELECT * FROM TEST_TABLE WHERE TESTID IN "\
                                   "(2, 4, 6, 8, 10) ORDER BY TESTID ASCENDING")
      a = r.fetch
      assert_equal(2, a[0])
      assert_equal('3.0', a[1])
      assert_equal(3.0, a[2])
      assert_nil(a[3])
      assert_nil(a[4])

      a = r.fetch
      assert(a[0] == 4)
      assert(a[1] == '10.0')
      assert(a[2] == 10.0)
      assert(a[3] == nil)
      assert(a[4] == nil)

      a = r.fetch
      assert(a[0] == 6)
      assert(a[1] == '21.0')
      assert(a[2] == 21.0)
      assert(a[3] == nil)
      assert(a[4] == nil)

      a = r.fetch
      assert(a[0] == 8)
      assert(a[1] == '36.0')
      assert(a[2] == 36.0)
      assert(a[3] == nil)
      assert(a[4] == nil)

      a = r.fetch
      assert(a[0] == 10)
      assert(a[1] == '55.0')
      assert(a[2] == 55.0)
      assert(a[3] == nil)
      assert(a[4] == nil)
      
      r.close
      
      @transactions[0].commit
      
      @connections[0].start_transaction do |tx|
         s = @connections[0].create_statement("UPDATE TEST_TABLE SET TESTSTAMP = NULL")
         s.exec(nil, tx)
         s.close
         
         r = tx.execute("SELECT TESTSTAMP FROM TEST_TABLE")
         total = 0
         r.each do |row|
            assert(row[0] == nil)
            total = total + 1
         end
         assert(total == 20)
         r.close
      end
      
      a = []
      t = nil
      @connections[0].start_transaction do |tx|
         # Perform an insert via a parameterized statement.
         s = @connections[0].create_statement(
                           "INSERT INTO TEST_TABLE (TESTID, TESTTEXT, "\
                           "TESTFLOAT, TESTSTAMP) VALUES(?, ?, ?, ?)")
         t = Time.new
         s.exec([25000, 'La la la', 3.14, t], tx)
         s.close
         
         # Fetch the record and check the data.
         r = tx.execute("SELECT TESTTEXT, TESTFLOAT, TESTSTAMP, cast(TESTFLOAT as varchar(20)) as TESTFLOAT_TXT FROM "\
                        "TEST_TABLE WHERE TESTID = 25000")
         a = r.fetch
         r.close
      end
      assert_equal('3.14', a[3])
      assert_equal('La la la', a[0])
      assert_equal(3.14, a[1])
      assert_equal(t.to_i, a[2].to_i)
      
      @connections[0].execute_immediate("DELETE FROM TEST_TABLE WHERE TESTID "\
                                        "IN (1, 3, 5, 7, 9, 12, 14, 16, 18, 20)")
      @database.connect(DB_USER_NAME, DB_PASSWORD) do |cxn|
         a = []
         cxn.start_transaction do |tx|
            r = tx.execute("SELECT COUNT(*) FROM TEST_TABLE")
            a = r.fetch
            r.close
         end
         assert(a[0] == 11)
      end
   end
end


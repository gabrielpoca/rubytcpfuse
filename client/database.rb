require 'sqlite3'
require 'active_record'

# Database is not to be instantiated.
# It supports one table:
# 1. logs. Stores every message for a session in the database.

class Database

  def self.initialize_database
    ActiveRecord::Base.establish_connection({adapter: 'sqlite3', database: 'client.db'})

    sql = 'CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT);'

            st = ActiveRecord::Base.connection.raw_connection.prepare(sql)
            st.execute
  end

  initialize_database

end

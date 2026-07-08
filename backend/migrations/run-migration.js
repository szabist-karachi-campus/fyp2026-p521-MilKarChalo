#!/usr/bin/env node

/**
 * Database Migration Runner
 * 
 * Executes SQL migrations to create performance indexes for the recurring round trips feature.
 * 
 * Usage: node run-migration.js
 */

import mysql from 'mysql2/promise';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: '../.env' });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || '',
  database: process.env.DB_NAME || 'milkarchalo',
  port: process.env.DB_PORT || 3306,
  waitForConnections: true,
  connectionLimit: 5
});

async function runMigration() {
  let connection;
  try {
    connection = await pool.getConnection();
    console.log('✓ Connected to database:', process.env.DB_NAME || 'milkarchalo');

    // Read migration file
    const migrationFile = path.join(__dirname, '001_create_performance_indexes.sql');
    const sql = fs.readFileSync(migrationFile, 'utf8');
    
    console.log('\n📋 Executing migration: 001_create_performance_indexes.sql\n');
    console.log('─'.repeat(70));

    // Split SQL by semicolon and execute each statement
    const statements = sql
      .split(';')
      .map(stmt => stmt.trim())
      .filter(stmt => stmt.length > 0 && !stmt.startsWith('--'));

    for (const statement of statements) {
      try {
        console.log(`\nExecuting: ${statement.substring(0, 70)}...`);
        await connection.execute(statement);
        console.log('✓ Successfully executed');
      } catch (error) {
        if (error.code === 'ER_DUP_KEYNAME') {
          console.log('⚠ Index already exists (skipping)');
        } else {
          throw error;
        }
      }
    }

    console.log('\n' + '─'.repeat(70));
    console.log('\n✓ Migration completed successfully!\n');

    // Verify indexes were created
    console.log('📊 Verifying indexes...\n');
    await verifyIndexes(connection);

  } catch (error) {
    console.error('\n❌ Migration failed:', error.message);
    process.exit(1);
  } finally {
    if (connection) connection.release();
    await pool.end();
  }
}

async function verifyIndexes(connection) {
  const indexesToCheck = [
    { table: 'bookings', indexName: 'idx_bookings_booking_group_id' },
    { table: 'bookings', indexName: 'idx_bookings_ride_occurrence' },
    { table: 'ride_occurrences', indexName: 'idx_ride_occurrences_date_status' },
    { table: 'rides', indexName: 'idx_rides_recurrence_group' }
  ];

  console.log('Checking indexes in database:\n');
  
  for (const { table, indexName } of indexesToCheck) {
    try {
      const [indexes] = await connection.execute(
        `SHOW INDEXES FROM ${table} WHERE Key_name = ?`,
        [indexName]
      );
      
      if (indexes.length > 0) {
        const index = indexes[0];
        console.log(`✓ ${table}.${indexName}`);
        console.log(`  Columns: ${index.Column_name} (Seq: ${index.Seq_in_index})`);
        console.log(`  Cardinality: ${index.Cardinality}`);
      } else {
        console.log(`✗ ${table}.${indexName} - NOT FOUND`);
      }
    } catch (error) {
      console.error(`✗ ${table}.${indexName} - Error checking: ${error.message}`);
    }
  }

  console.log('\n' + '─'.repeat(70) + '\n');
}

// Run migration
runMigration();

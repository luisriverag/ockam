USE ROLE ACCOUNTADMIN;

--Create Role
CREATE ROLE IF NOT EXISTS MSSQL_CONNECTOR_ROLE;
GRANT ROLE MSSQL_CONNECTOR_ROLE TO ROLE ACCOUNTADMIN;

--Create Database
CREATE DATABASE IF NOT EXISTS MSSQL_CONNECTOR_DB;
GRANT OWNERSHIP ON DATABASE MSSQL_CONNECTOR_DB TO ROLE MSSQL_CONNECTOR_ROLE COPY CURRENT GRANTS;

USE DATABASE MSSQL_CONNECTOR_DB;

--Create Warehouse
CREATE OR REPLACE WAREHOUSE MSSQL_CONNECTOR_WH WITH WAREHOUSE_SIZE='X-SMALL';
GRANT USAGE ON WAREHOUSE MSSQL_CONNECTOR_WH TO ROLE MSSQL_CONNECTOR_ROLE;

--Create compute pool
CREATE COMPUTE POOL IF NOT EXISTS MSSQL_CONNECTOR_CP
  MIN_NODES = 1
  MAX_NODES = 5
  INSTANCE_FAMILY = CPU_X64_XS;

GRANT USAGE ON COMPUTE POOL MSSQL_CONNECTOR_CP TO ROLE MSSQL_CONNECTOR_ROLE;
GRANT MONITOR ON COMPUTE POOL MSSQL_CONNECTOR_CP TO ROLE MSSQL_CONNECTOR_ROLE;

--Create schema
CREATE SCHEMA IF NOT EXISTS MSSQL_CONNECTOR_SCHEMA;
GRANT ALL PRIVILEGES ON SCHEMA MSSQL_CONNECTOR_SCHEMA TO ROLE MSSQL_CONNECTOR_ROLE;

USE SCHEMA MSSQL_CONNECTOR_SCHEMA;

--Create Image Repository
CREATE IMAGE REPOSITORY IF NOT EXISTS MSSQL_CONNECTOR_REPOSITORY;
GRANT READ ON IMAGE REPOSITORY MSSQL_CONNECTOR_REPOSITORY TO ROLE MSSQL_CONNECTOR_ROLE;

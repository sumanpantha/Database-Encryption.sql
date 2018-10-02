--------SERVER 1     192.168.19.153,1434  (SQLNODE2)   ------

USE master

CREATE DATABASE TestTDE ON PRIMARY
(
NAME = 'TestTDE',
fILENAME = 'c:\sqldata\TestTDE.mdf',
SIZE = 10240KB,
FILEGROWTH = 1024KB
)
LOG ON 
(
NAME = 'TestTDE_Log',
fILENAME = 'c:\sqldata\TestTDE.ldf',
SIZE = 10240KB,
FILEGROWTH = 1024KB
)
go


--Create table in TestTDE Database 
USE TestTDE
DROP TABLE TestTable
CREATE TABLE TestTable
(
Field1 int,
Field2 varchar(100),
Field3 DECIMAL(5,2)
)

-- Insert into TestTable Table in TestTDE Database 
INSERT INTO TestTable
select 1 as Field1, 'Value 1' as Field2, '10.00' as Field3 union all
select 2 as Field1, 'Value 2' as Field2, '20.00' as Field3 union all
select 3 as Field1, 'Value 3' as Field2, '30.00' as Field3 


SELECT * FROM TestTable

-- Backup TestTDE Database 

BACKUP DATABASE TestTDE TO DISK = 'C:\Backup\TestTDE.bak'  WITH INIT, COMPRESSION

/*
	Lets create the DB master key for use in TDE
*/

USE master
go 
CREATE MASTER KEY 
ENCRYPTION BY PASSWORD = '8Square@'
go

/*
USE master;  
DROP MASTER KEY;  
DROP CERTIFICATE MyServerCert
*/


select  
	    name,
		key_length,
		algorithm_desc,
		create_date,
		modify_date
from sys.symmetric_keys

/*
	Now, lets create a Certificate that will be used 
	in the Encryption Hierarchy
*/

CREATE CERTIFICATE MyServerCert
WITH SUBJECT = 'My DEK Certificate'
go


select  
		[name],
		pvt_key_encryption_type_desc,
		[subject],
		[start_date],
		[expiry_date],
		pvt_key_last_backup_date
from sys.certificates
where name not like '%##%'	  


/*
	You must be the Database that you are creating 
	the key for, Then create the key for the Encryption,
	You can choose the following Encryption algorithms.
	AES_128, AES_192, AES_256, TRIPLE_DES_3KEY
*/


USE TestTDE

CREATE DATABASE ENCRYPTION KEY 
WITH ALGORITHM =AES_128
ENCRYPTION BY SERVER CERTIFICATE MyServerCert

/* The Warning given by the system
Warning: The certificate used for encrypting the database encryption key has not been backed up. 
You should immediately back up the certificate and the private key associated with the certificate. 
If the certificate ever becomes unavailable or if you must restore or attach the database on another server, 
you must have backups of both the certificate and the private key or you will not be able to open the database.
*/


USE master

BACKUP CERTIFICATE MyServerCert
TO FILE = 'C:\Backup\MyServerCert.cer'
WITH PRIVATE KEY (FILE = 'C:\Backup\MyServerCert.pvk',
ENCRYPTION BY PASSWORD = '8Square@')
go


/* Check  the certificate Private key Backup */

select  
		[name],
		pvt_key_encryption_type_desc,
		[subject],
		[start_date],
		[expiry_date],
		pvt_key_last_backup_date
from sys.certificates
where name not like '%##%'	  

/*  Now set the Encryption mode ON  */

ALTER DATABASE TestTDE
SET ENCRYPTION ON 
GO


USE master

select 
		db.name,
		db.is_encrypted,
		dm.encryption_state,
		dm.percent_complete,
		dm.key_algorithm,
		dm.key_length
from sys.databases db 
left outer join sys.dm_database_encryption_keys dm on db.database_id = dm.database_id
		
/*

0 = No database encryption key present, no encryption
1 =  Unencrypted
2 = Encryption in progress 
3 = Encrypted 
4 = Key change in progress
5 = Decryption in progress
6 = Protection change in progress
(The certificate or asymmetric key that is encrypting 
the database Encryption key is being changed.) 

*/

SELECT 
		 name, 
		 create_date
FROM sys.databases 
WHERE [name] = 'TestTDE'



SELECT 
		 name, 
		 db.create_date as db_created, 
		 dm.create_date as enc_created
FROM sys.databases  db 
left outer join sys.dm_database_encryption_keys dm on db.database_id = dm.database_id
WHERE [name] = 'TestTDE'

-- Backup TestTDE Database 
USE master
BACKUP DATABASE TestTDE TO DISK = 'C:\Backup\TestTDE_enc.bak'  WITH INIT, COMPRESSION


---------------------  Now SWITCH to other SERVER with the encrypted backup--------------

---- SERVER 2 192.168.19.130 (CentOS Linux)
/*

The backup file is moved to Linux System where we have another instance of SQL SERVER
on path /SQLBackup/

*/

RESTORE FILELISTONLY FROM DISK =  '/SQLBackup/TestTDE_enc.bak'
GO

/*
ERROR MESSAGE
	Msg 33111, Level 16, State 3, Line 3
Cannot find server certificate with thumbprint '0xA786CAACAEDB15D728BF4236280659D8E7E3BB06'.
Msg 3013, Level 16, State 1, Line 3
RESTORE FILELIST is terminating abnormally.
*/

-- Now need to follow following steps to Resport the DB files to other server than the SERVER 1

USE master
go 

-- We can create MASTER KEY by two ways 
--1. By creating Master key with password the password need not to be same as of SERVER 1
--2. By restoring the backup of the Master Key of SERVER 1

CREATE MASTER KEY 
ENCRYPTION BY PASSWORD = '8Square@'
go 

/*

But is where critical nature is though the Certificate name can be different than the previous one
but this should have to be the same

*/

CREATE CERTIFICATE MyServerCert
FROM FILE = '/SQLBackup/MyServerCert.cer'
WITH PRIVATE KEY (FILE = '/SQLBackup/MyServerCert.pvk',
DECRYPTION BY PASSWORD = '8Square@')

select  
		[name],
		pvt_key_encryption_type_desc,
		[subject],
		[start_date],
		[expiry_date],
		pvt_key_last_backup_date
from sys.certificates
where name not like '%##%'	

/*
Now RESTORE backup file it will be RESTORED SUCCESSFULLY
*/

RESTORE FILELISTONLY FROM DISK =  '/SQLBackup/TestTDE_enc.bak'

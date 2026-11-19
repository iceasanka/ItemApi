/* =============================================================================
   U073_BackOffice_ChequeSupplierContacts.sql   (2026-11-19)
   Update for a back office db (easyway) that is ALREADY deployed. SQL Server 2008 R2 and newer.
   Safe to run again. Needs U023 (settings) and U072 (the supplier columns). Values set by an admin are kept.

   What changes:
     - setting Cheque.SupplierContacts (group Cheques, bool, default ON): a cheque for a supplier is not printed
       until that supplier's Ref phone AND Area manager phone are filled in. Print on the Cheque page then opens
       the supplier's edit box to fill them. ItemApi refuses the print too. Meant for a few months while the
       supplier data is filled in; turn it off on Settings > Cheques after that.
   Same change in the full script: 44_BackOffice_ChequeSupplierContacts.sql.

   Run:  sqlcmd -S <server> -d easyway -E -I -b -i U073_BackOffice_ChequeSupplierContacts.sql
   Then: the new ItemApi and back office pages of 2026-11-19.
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Setting', 'U') IS NULL OR COL_LENGTH('dbo.z_tb_Supplier', 'AreaMgrPhone') IS NULL
BEGIN
    RAISERROR('Run U072_BackOffice_SupplierContacts.sql first on a back office database with U023 (z_tb_Setting / z_tb_Supplier.AreaMgrPhone not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO

-- the setting (label, help and default set again on every run; the chosen value is kept)
DECLARE @s TABLE (SettingKey VARCHAR(50), GroupName NVARCHAR(30), Label NVARCHAR(100), Descrip NVARCHAR(400), Scope INT,
                  ValueType VARCHAR(10), Options NVARCHAR(400), DefaultValue NVARCHAR(200), SortOrder INT);
INSERT @s VALUES
 ('Cheque.SupplierContacts', N'Cheques', N'Supplier Ref phone and Area manager phone needed to print',
  N'On: a cheque for a supplier does not print until the supplier''s Ref phone and Area manager phone are filled in - Print opens the supplier to fill them. For the months the supplier data is being filled in; turn off after.',
  1, 'bool', NULL, N'1', 300);

UPDATE t SET GroupName = s.GroupName, Label = s.Label, Descrip = s.Descrip, Scope = s.Scope, ValueType = s.ValueType,
             Options = s.Options, DefaultValue = s.DefaultValue, SortOrder = s.SortOrder
FROM dbo.z_tb_Setting t JOIN @s s ON s.SettingKey = t.SettingKey;

INSERT dbo.z_tb_Setting (SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder)
SELECT SettingKey, GroupName, Label, Descrip, Scope, ValueType, Options, DefaultValue, SortOrder
FROM @s s WHERE NOT EXISTS (SELECT 1 FROM dbo.z_tb_Setting t WHERE t.SettingKey = s.SettingKey);
GO

SET NOEXEC OFF;
GO
PRINT 'U073_BackOffice_ChequeSupplierContacts done: setting Cheque.SupplierContacts.';
GO

CREATE DATABASE ClinicManagementDB;
GO

USE ClinicManagementDB;
GO

CREATE TABLE Specialties (
    SpecialtyID INT IDENTITY (1, 1) PRIMARY KEY,
    SpecialtyName NVARCHAR (100) NOT NULL UNIQUE,
    FloorNumber TINYINT NULL,
    MonthlyBudget DECIMAL(14, 2) NOT NULL DEFAULT 0,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE Doctors (
    DoctorID INT IDENTITY (1, 1) PRIMARY KEY,
    FirstName NVARCHAR (50) NOT NULL,
    LastName NVARCHAR (50) NOT NULL,
    LicenseNumber NVARCHAR (50) NOT NULL UNIQUE,
    ConsultationFee DECIMAL(10, 2) NOT NULL CHECK (ConsultationFee >= 0),
    SpecialtyID INT NOT NULL,
    HireDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    CONSTRAINT FK_Doctors_Specialties FOREIGN KEY (SpecialtyID) 
        REFERENCES Specialties (SpecialtyID) ON UPDATE CASCADE ON DELETE NO ACTION
);

CREATE TABLE Patients (
    PatientID INT IDENTITY (1, 1) PRIMARY KEY,
    FirstName NVARCHAR (50) NOT NULL,
    LastName NVARCHAR (50) NOT NULL,
    PersonalID NVARCHAR (11) NOT NULL UNIQUE CHECK (LEN(PersonalID) = 11),
    DateOfBirth DATE NOT NULL,
    BloodType NVARCHAR(3) NULL CHECK (BloodType IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    RegistrationDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE Appointments (
    AppointmentID INT IDENTITY (1, 1) PRIMARY KEY,
    PatientID INT NOT NULL,
    DoctorID INT NOT NULL,
    AppointmentDate DATETIME2 NOT NULL,
    Status NVARCHAR (20) NOT NULL CONSTRAINT DF_Appointments_Status DEFAULT 'Scheduled' 
        CHECK (Status IN ('Scheduled', 'Completed', 'Cancelled', 'NoShow')),
    Notes NVARCHAR (500) NULL,
    CONSTRAINT FK_Appointments_Patients FOREIGN KEY (PatientID) 
        REFERENCES Patients (PatientID) ON DELETE CASCADE,
    CONSTRAINT FK_Appointments_Doctors FOREIGN KEY (DoctorID) 
        REFERENCES Doctors (DoctorID) ON DELETE CASCADE,
    CONSTRAINT UQ_Appointments_DoctorTime UNIQUE (DoctorID, AppointmentDate)
);

CREATE TABLE SystemAuditLogs (
    LogID INT IDENTITY (1, 1) PRIMARY KEY,
    TableName NVARCHAR (50) NOT NULL,
    RecordID INT NOT NULL,
    ActionType NVARCHAR (20) NOT NULL,
    OldValue NVARCHAR (MAX) NULL,
    NewValue NVARCHAR (MAX) NULL,
    ChangedBy NVARCHAR (128) NOT NULL DEFAULT SUSER_SNAME(),
    ChangeDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE ErrorLogs (
    ErrorLogID INT IDENTITY (1, 1) PRIMARY KEY,
    ErrorNumber INT NULL,
    ErrorSeverity INT NULL,
    ErrorState INT NULL,
    ErrorProcedure NVARCHAR (200) NULL,
    ErrorLine INT NULL,
    ErrorMessage NVARCHAR (4000) NULL,
    ErrorDateTime DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    LoggedBy NVARCHAR (128) NOT NULL DEFAULT SUSER_SNAME()
);

CREATE INDEX IX_Doctors_SpecialtyID ON Doctors (SpecialtyID);
CREATE INDEX IX_Appointments_PatientID ON Appointments (PatientID);
CREATE INDEX IX_Appointments_DoctorID ON Appointments (DoctorID);
CREATE INDEX IX_Appointments_Date ON Appointments (AppointmentDate);

INSERT INTO Specialties (SpecialtyName, FloorNumber, MonthlyBudget)
VALUES
    ('Cardiology', 3, 150000.00),
    ('Neurology', 4, 120000.00),
    ('Pediatrics', 2, 90000.00);

INSERT INTO Doctors (FirstName, LastName, LicenseNumber, ConsultationFee, SpecialtyID)
VALUES
    ('დავით', 'მაისურაძე', 'LIC-10045', 70.00, 1),
    ('თამარ', 'შენგელია', 'LIC-20098', 85.00, 2),
    ('ლაშა', 'დვალი', 'LIC-30012', 50.00, 3);

INSERT INTO Patients (FirstName, LastName, PersonalID, DateOfBirth, BloodType)
VALUES
    ('ნინო', 'გოგოლაძე', '01011012345', '1985-04-12', 'A+'),
    ('გიორგი', 'მამალაძე', '01022054321', '1990-11-23', 'O+'),
    ('სოფო', 'ჯაფარიძე', '01033098765', '2015-08-05', 'B-');

INSERT INTO Appointments (PatientID, DoctorID, AppointmentDate, Status, Notes)
VALUES
    (1, 1, '2026-10-15 10:00:00', 'Scheduled', 'Routine heart checkup'),
    (2, 2, '2026-10-15 11:30:00', 'Scheduled', 'Migraine issues'),
    (3, 3, '2026-10-16 09:00:00', 'Completed', 'Vaccination');

GO

CREATE OR ALTER VIEW v_Upcoming_Appointments AS
SELECT
    a.AppointmentID,
    p.FirstName + ' ' + p.LastName AS PatientName,
    p.PersonalID,
    d.FirstName + ' ' + d.LastName AS DoctorName,
    s.SpecialtyName,
    a.AppointmentDate,
    a.Status
FROM
    Appointments AS a
    INNER JOIN Patients AS p ON a.PatientID = p.PatientID
    INNER JOIN Doctors AS d ON a.DoctorID = d.DoctorID
    INNER JOIN Specialties AS s ON d.SpecialtyID = s.SpecialtyID
WHERE
    a.Status = 'Scheduled';
GO

CREATE OR ALTER TRIGGER trg_AppointmentStatus_Update
ON Appointments
AFTER UPDATE
AS 
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(Status)
    BEGIN
        INSERT INTO SystemAuditLogs (TableName, RecordID, ActionType, OldValue, NewValue, ChangedBy)
        SELECT
            'Appointments',
            i.AppointmentID,
            'STATUS_CHANGE',
            d.Status,
            i.Status,
            SUSER_SNAME()
        FROM inserted AS i
        INNER JOIN deleted AS d ON i.AppointmentID = d.AppointmentID
        WHERE i.Status <> d.Status;
    END
END;
GO

CREATE ROLE clinic_admin;
ALTER ROLE db_owner ADD MEMBER clinic_admin;

CREATE ROLE front_desk_receptionist;

GRANT SELECT, INSERT, UPDATE ON dbo.Patients TO front_desk_receptionist;
GRANT SELECT, INSERT, UPDATE ON dbo.Appointments TO front_desk_receptionist;
GRANT SELECT ON dbo.Doctors TO front_desk_receptionist;

DENY DELETE ON dbo.Patients TO front_desk_receptionist;
DENY DELETE ON dbo.Appointments TO front_desk_receptionist;
GO

CREATE OR ALTER PROCEDURE usp_BackupClinicDatabase
    @BackupDirectory NVARCHAR(260) = N'D:\SQLBackups\'
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        DECLARE @FileName NVARCHAR(300);
        SET @FileName = @BackupDirectory + N'ClinicManagementDB_Full_' 
                      + FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + N'.bak';
        
        BACKUP DATABASE ClinicManagementDB
        TO DISK = @FileName
        WITH INIT, COMPRESSION, CHECKSUM,
             NAME = N'ClinicManagementDB-Full Backup';
    END TRY
    BEGIN CATCH
        INSERT INTO ErrorLogs (ErrorNumber, ErrorSeverity, ErrorState, ErrorProcedure, ErrorLine, ErrorMessage)
        VALUES (
            ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), 
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE()
        );
        THROW; 
    END CATCH
END;
GO
#!/usr/bin/env python3
"""Generates a fictional Wagonmaster Manifest export for tests and the Waypoint demo.

The data is invented (Infinite Improbability Corp). Record shapes follow the
published Azure Migrate REST API schemas, in the folder layout Manifest writes.
Deterministic: the same seed always produces the same export.

Usage: python3 tools/New-SampleExport.py [output-folder] [azure|azure-local]

  azure        Mixed estate being assessed for and migrated to Azure (default).
  azure-local  VMware estate being migrated to Azure Local. Azure Migrate has no
               assessment for Azure Local, so that export has none.
"""
import csv, json, os, random, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'samples/manifest-export'
TARGET = sys.argv[2] if len(sys.argv) > 2 else 'azure'
AZL = TARGET == 'azure-local'
R = random.Random(20261112)
SUB = '00000000-0000-0000-0000-000000000000'
RG = 'rg-iic-azl-migrate-01' if AZL else 'rg-iic-migrate-01'
PROJECT = 'iic-azurelocal-migrate' if AZL else 'iic-migrate'
BASE = f'/subscriptions/{SUB}/resourceGroups/{RG}/providers'
NOW = '2026-11-10T14:00:00Z'

OS_WIN = [('Windows Server 2012 R2 Standard', '6.3', 'Unsupported'), ('Windows Server 2016 Datacenter', '10.0.14393', 'Extended'),
          ('Windows Server 2019 Datacenter', '10.0.17763', 'Mainstream'), ('Windows Server 2019 Standard', '10.0.17763', 'Mainstream'),
          ('Windows Server 2022 Datacenter', '10.0.20348', 'Mainstream'), ('Windows Server 2008 R2 Enterprise', '6.1', 'Unsupported')]
OS_LIN = [('Red Hat Enterprise Linux 7.9', '7.9', 'Extended'), ('Red Hat Enterprise Linux 8.8', '8.8', 'Mainstream'),
          ('Ubuntu 20.04 LTS', '20.04', 'Mainstream'), ('Ubuntu 22.04 LTS', '22.04', 'Mainstream'), ('CentOS Linux 7', '7.9', 'Unsupported'),
          ('SUSE Linux Enterprise Server 15 SP4', '15.4', 'Mainstream')]
ROLES = ['app', 'web', 'sql', 'file', 'dc', 'batch', 'api', 'etl', 'mgmt', 'print']
SIZES = [('Standard_D2s_v5', 2, 8, 70.08), ('Standard_D4s_v5', 4, 16, 140.16), ('Standard_D8s_v5', 8, 32, 280.32),
         ('Standard_E4s_v5', 4, 32, 183.96), ('Standard_E8s_v5', 8, 64, 367.92), ('Standard_F4s_v2', 4, 8, 123.37),
         ('Standard_B2ms', 2, 8, 60.74), ('Standard_D16s_v5', 16, 64, 560.64), ('Standard_E16s_v5', 16, 128, 735.84)]
SOFTWARE = [('Microsoft SQL Server 2019', 'Microsoft Corporation', '15.0.2000.5'), ('Microsoft .NET Framework 4.8', 'Microsoft Corporation', '4.8.04084'),
            ('Internet Information Services', 'Microsoft Corporation', '10.0'), ('Apache Tomcat 9', 'Apache Software Foundation', '9.0.80'),
            ('OpenJDK 11', 'Eclipse Adoptium', '11.0.20'), ('CrowdStrike Falcon Sensor', 'CrowdStrike, Inc.', '7.05'),
            ('Veeam Agent', 'Veeam Software', '6.0.2'), ('VMware Tools', 'VMware, Inc.', '12.3.0'), ('Splunk Universal Forwarder', 'Splunk, Inc.', '9.1.1'),
            ('nginx', 'F5, Inc.', '1.24.0'), ('PostgreSQL 14', 'PostgreSQL Global Development Group', '14.9'), ('Python 3.9', 'Python Software Foundation', '3.9.18'),
            ('Microsoft Monitoring Agent', 'Microsoft Corporation', '10.20.18069'), ('7-Zip 22.01', 'Igor Pavlov', '22.01'), ('Notepad++', 'Notepad++ Team', '8.5.7')]

datasets = {}
manifest_rows = []

def add(name, records):
    datasets.setdefault(name, []).extend(records)

def make_machine(i, site_kind, site_name, site_id):
    win = R.random() < 0.68
    os_name, os_ver, support = R.choice(OS_WIN if win else OS_LIN)
    role = R.choice(ROLES)
    name = f'iic-{role}-{i:03d}'
    cores = R.choice([2, 2, 4, 4, 4, 8, 8, 16])
    mem = cores * R.choice([2, 4, 4, 8]) * 1024
    ndisk = R.choice([1, 2, 2, 3, 4])
    disks = [{'uuid': f'6000C29{R.randrange(16**8):08x}', 'label': f'Hard disk {d + 1}', 'maxSizeInBytes': R.choice([64, 128, 128, 256, 512, 1024]) * 1024 ** 3,
              'diskProvisioningPolicy': R.choice(['thin', 'thick'])} for d in range(ndisk)]
    ip = f'10.{R.randrange(10, 14)}.{R.randrange(0, 250)}.{R.randrange(10, 250)}'
    props = {
        'displayName': name,
        'operatingSystemDetails': {'osType': 'windowsguest' if win else 'linuxguest', 'osName': os_name, 'osVersion': os_ver, 'osArchitecture': 'x64'},
        'numberOfProcessorCore': cores, 'allocatedMemoryInMB': mem, 'disks': disks,
        'networkAdapters': [{'nicId': '4000', 'macAddress': '00:50:56:%02x:%02x:%02x' % (R.randrange(256), R.randrange(256), R.randrange(256)),
                             'ipAddressList': [ip], 'networkName': R.choice(['VLAN-110-App', 'VLAN-120-Data', 'VLAN-130-Web', 'VLAN-140-Mgmt'])}],
        'powerStatus': 'ON' if R.random() < 0.93 else 'OFF',
        'productSupportStatus': {'supportStatus': support},
        'numberOfApplications': R.randrange(8, 60), 'isDeleted': False,
        'createdTimestamp': '2026-11-03T09:12:00Z', 'updatedTimestamp': NOW,
    }
    if site_kind == 'VMware':
        props.update({'vmFqdn': f'{name}.iic.example', 'vCenterFQDN': 'vcenter01.iic.example', 'hostName': f'esx{R.randrange(1, 9):02d}.iic.example',
                      'dependencyMapping': 'Enabled' if R.random() < 0.8 else 'Disabled'})
        rtype = 'Microsoft.OffAzure/VMwareSites/machines'
    elif site_kind == 'HyperV':
        props.update({'clusterFqdn': 'hvclus01.iic.example', 'hostFqdn': f'hv{R.randrange(1, 5):02d}.iic.example', 'generation': 2})
        rtype = 'Microsoft.OffAzure/HyperVSites/machines'
    else:
        props.update({'fqdn': f'{name}.iic.example', 'hydratedFqdn': f'{name}.iic.example'})
        rtype = 'Microsoft.OffAzure/ServerSites/machines'
    mid = f'{site_id}/machines/{name}-{R.randrange(16**6):06x}'
    return {'_Project': PROJECT, '_Site': site_name, 'id': mid, 'name': mid.split('/')[-1], 'type': rtype, 'properties': props}, role, win

sites = [('VMware', 'iic-vmware-site', 160, 'Discovery_VMware_Machines', 'VMwareSites'),
         ('HyperV', 'iic-hyperv-site', 60, 'Discovery_HyperV_Machines', 'HyperVSites'),
         ('Server', 'iic-server-site', 20, 'Discovery_Physical_Machines', 'ServerSites')]
if AZL:
    # Azure Local migration projects pair one source appliance with one target appliance.
    sites = [('VMware', 'iic-vmware-site', 180, 'Discovery_VMware_Machines', 'VMwareSites')]
machines = []
n = 0
for kind, sname, count, ds, rt in sites:
    sid = f'{BASE}/Microsoft.OffAzure/{rt}/{sname}'
    add('Discovery_Sites', [{'_Project': PROJECT, '_Site': sname, 'id': sid, 'name': sname, 'type': f'Microsoft.OffAzure/{rt}', 'location': 'eastus',
                             'properties': {'applianceName': f'iic-appliance-{kind.lower()}', 'provisioningState': 'Succeeded',
                                            'serviceEndpoint': 'https://example.invalid', 'discoverySolutionId': f'{BASE}/Microsoft.Migrate/migrateProjects/{PROJECT}/solutions/Servers-Discovery-ServerDiscovery'}}])
    for _ in range(count):
        n += 1
        m, role, win = make_machine(n, kind, sname, sid)
        add(ds, [m])
        machines.append((m, role, win, kind))
add('Discovery_VMware_vCenters', [{'_Project': PROJECT, '_Site': 'iic-vmware-site', 'id': f'{BASE}/Microsoft.OffAzure/VMwareSites/iic-vmware-site/vCenters/vcenter01',
                                   'name': 'vcenter01', 'properties': {'fqdn': 'vcenter01.iic.example', 'port': '443', 'version': '7.0.3', 'perfStatisticsLevels': {'pastDay': '2'}}}])
for h in range(1, 5) if not AZL else []:
    add('Discovery_HyperV_Hosts', [{'_Project': PROJECT, '_Site': 'iic-hyperv-site', 'id': f'{BASE}/Microsoft.OffAzure/HyperVSites/iic-hyperv-site/hosts/hv{h:02d}',
                                    'name': f'hv{h:02d}', 'properties': {'fqdn': f'hv{h:02d}.iic.example', 'version': '10.0.20348'}}])
if not AZL: add('Discovery_HyperV_Clusters', [{'_Project': PROJECT, '_Site': 'iic-hyperv-site', 'id': f'{BASE}/Microsoft.OffAzure/HyperVSites/iic-hyperv-site/clusters/hvclus01',
                                   'name': 'hvclus01', 'properties': {'fqdn': 'hvclus01.iic.example', 'functionalLevel': 12, 'status': 'Up'}}])

# SQL and web discovery
master = f'{BASE}/Microsoft.OffAzure/MasterSites/iic-master-site'
sqlsite = f'{master}/SqlSites/iic-sql-site'
websites = f'{master}/WebAppSites/iic-webapp-site'
sql_hosts = [m for m in machines if m[1] == 'sql' and m[2]]
sql_instances = []
for m, _, _, _ in sql_hosts:
    ver, vname, support = R.choice([('13.0.5026.0', 'SQL Server 2016', 'Extended'), ('14.0.2037.2', 'SQL Server 2017', 'Extended'),
                                    ('15.0.2000.5', 'SQL Server 2019', 'Mainstream'), ('11.0.7001.0', 'SQL Server 2012', 'Unsupported')])
    host = m['properties']['displayName']
    ndb = R.randrange(1, 9)
    inst = {'_Project': PROJECT, '_Site': 'iic-master-site', '_SqlSite': 'iic-sql-site', 'id': f'{sqlsite}/sqlServers/{host}-mssqlserver',
            'name': f'{host}-mssqlserver', 'type': 'Microsoft.OffAzure/MasterSites/SqlSites/sqlServers',
            'properties': {'sqlServerName': 'MSSQLSERVER', 'hostName': host, 'version': ver, 'sqlServerVersion': vname, 'edition': R.choice(['Standard', 'Enterprise', 'Developer']),
                           'numberOfUserDatabases': ndb, 'isHighAvailabilityEnabled': R.random() < 0.25, 'isClustered': False, 'status': 'Running',
                           'machineArmIds': [m['id']], 'productSupportStatus': {'supportStatus': support}, 'maxServerMemoryInUseInMb': R.choice([8192, 16384, 32768]),
                           'logicalCpuCount': m['properties']['numberOfProcessorCore']}}
    add('Discovery_Sql_Servers', [inst])
    sql_instances.append((inst, m))
    for d in range(ndb):
        dbn = R.choice(['Orders', 'Billing', 'Inventory', 'HR', 'Telemetry', 'Catalog', 'Reporting', 'Identity', 'Ledger']) + f'{d + 1:02d}'
        add('Discovery_Sql_Databases', [{'_Project': PROJECT, '_Site': 'iic-master-site', '_SqlSite': 'iic-sql-site', 'id': f'{sqlsite}/sqlDatabases/{host}-{dbn}',
                                         'name': f'{host}-{dbn}', 'properties': {'databaseName': dbn, 'sqlServerName': f'{host}\\MSSQLSERVER', 'hostName': host,
                                                                                'sizeMb': round(R.uniform(200, 180000), 1), 'compatibilityLevel': R.choice(['Compatibility110', 'Compatibility130', 'Compatibility150']),
                                                                                'status': 'Online'}}])
add('Discovery_SqlSites', [{'_Project': PROJECT, '_Site': 'iic-master-site', 'id': sqlsite, 'name': 'iic-sql-site', 'properties': {'provisioningState': 'Succeeded'}}])
add('Discovery_WebAppSites', [{'_Project': PROJECT, '_Site': 'iic-master-site', 'id': websites, 'name': 'iic-webapp-site', 'properties': {'provisioningState': 'Succeeded'}}])
add('Discovery_Sites', [{'_Project': PROJECT, '_Site': 'iic-master-site', 'id': master, 'name': 'iic-master-site', 'type': 'Microsoft.OffAzure/MasterSites',
                         'properties': {'sites': [f'{BASE}/Microsoft.OffAzure/{rt}/{sn}' for _, sn, _, _, rt in sites], 'provisioningState': 'Succeeded'}}])
web_apps = []
for m, role, win, _ in [x for x in machines if x[1] in ('web', 'api')]:
    host = m['properties']['displayName']
    for a in range(R.randrange(1, 4)):
        app = R.choice(['portal', 'checkout', 'intranet', 'partner-api', 'reports', 'catalog', 'auth']) + f'-{a + 1}'
        if win:
            rec = {'_Project': PROJECT, '_Site': 'iic-master-site', '_WebAppSite': 'iic-webapp-site', 'id': f'{websites}/iisWebApplications/{host}-{app}', 'name': f'{host}-{app}',
                   'properties': {'displayName': app, 'webServerName': f'{host}-iis', 'serverType': 'IIS', 'machineArmIds': [m['id']],
                                  'frameworks': [{'name': '.NET Framework', 'version': R.choice(['4.6.2', '4.7.2', '4.8'])}],
                                  'virtualApplications': [{'virtualPath': '/', 'physicalPath': f'D:\\inetpub\\{app}'}], 'bindings': [{'protocol': 'https', 'port': '443'}]}}
            add('Discovery_IIS_WebApps', [rec])
        else:
            rec = {'_Project': PROJECT, '_Site': 'iic-master-site', '_WebAppSite': 'iic-webapp-site', 'id': f'{websites}/tomcatWebApplications/{host}-{app}', 'name': f'{host}-{app}',
                   'properties': {'displayName': app, 'webServerName': f'{host}-tomcat', 'serverType': 'Tomcat', 'machineArmIds': [m['id']],
                                  'frameworks': [{'name': 'Java', 'version': R.choice(['8', '11', '17'])}], 'bindings': [{'protocol': 'http', 'port': '8080'}]}}
            add('Discovery_Tomcat_WebApps', [rec])
        web_apps.append(rec)

# Software inventory (subset of machines, as -IncludeSoftwareInventory would return)
for m, _, _, _ in machines:
    apps = R.sample(SOFTWARE, R.randrange(4, 10))
    add('Discovery_SoftwareInventory', [{'_Project': PROJECT, '_Site': m['_Site'], '_Machine': m['properties']['displayName'], '_MachineId': m['id'],
                                         'id': m['id'] + '/softwareInventories/default', 'name': 'default',
                                         'properties': {'appsAndRoles': {'applications': [{'name': a, 'provider': p, 'version': v} for a, p, v in apps],
                                                                         'features': [{'name': 'File-Services', 'featureType': 'Role'}] if R.random() < 0.3 else []}}}])

if AZL:
    # Replication to Azure Local is tracked in a Microsoft.DataReplication vault.
    rvault = f'{BASE}/Microsoft.DataReplication/replicationVaults/iic-azl-replicationvault'
    cluster = f'/subscriptions/{SUB}/resourceGroups/rg-iic-azl-prd-01/providers/Microsoft.AzureStackHCI/clusters/iic-azl-clus01'
    azl_states = [('Protected', 'Ready to migrate', 'Normal'), ('Protected', 'Ready to migrate', 'Normal'), ('Protected', 'Ready to migrate', 'Normal'),
                  ('InitialReplicationInProgress', 'Initial replication in progress', 'Normal'), ('PlannedFailoverCompleted', 'Migration completed', 'Normal'),
                  ('PlannedFailoverCompleted', 'Migration completed', 'Normal'), ('EnablingFailed', 'Enabling replication failed', 'Critical'),
                  ('PlannedFailoverInProgress', 'Migration in progress', 'Normal')]
    for m, _, _, _ in [x for x in machines if x[1] in ('web', 'api', 'batch', 'app', 'file')][:64]:
        st, desc, health = R.choice(azl_states)
        p = m['properties']
        done = st == 'PlannedFailoverCompleted'
        add('Migration_DataReplication_ProtectedItems', [{'_Project': PROJECT, '_Vault': 'iic-azl-replicationvault',
            'id': f"{rvault}/protectedItems/{m['name']}", 'name': m['name'], 'type': 'Microsoft.DataReplication/replicationVaults/protectedItems',
            'properties': {'policyName': 'iic-azl-replicationvaultVMwareToAzStackHCIpolicy', 'provisioningState': 'Succeeded',
                           'protectionState': st, 'protectionStateDescription': desc, 'replicationHealth': health,
                           'testFailoverState': 'None', 'resynchronizationState': 'None', 'fabricObjectName': p['displayName'],
                           'allowedJobs': ['PlannedFailover', 'DisableProtection'] if st == 'Protected' else ['DisableProtection'],
                           'lastSuccessfulPlannedFailoverTime': '2026-11-10T03:40:00Z' if done else None,
                           'healthErrors': [{'code': 'EnableProtectionFailed', 'severity': 'Error', 'message': 'The disk could not be read from the source.'}] if health == 'Critical' else [],
                           'customProperties': {'instanceType': 'VMwareToAzStackHCI', 'sourceVmName': p['displayName'], 'targetVmName': p['displayName'],
                                                'targetHciClusterId': cluster, 'targetAzStackHciClusterName': 'iic-azl-clus01',
                                                'targetArcClusterCustomLocationId': f'/subscriptions/{SUB}/resourceGroups/rg-iic-azl-prd-01/providers/Microsoft.ExtendedLocation/customLocations/iic-azl-cl01',
                                                'targetResourceGroupId': f'/subscriptions/{SUB}/resourceGroups/rg-iic-azl-workloads-01', 'customLocationRegion': 'eastus',
                                                'targetCpuCores': p['numberOfProcessorCore'], 'targetMemoryInMegaBytes': p['allocatedMemoryInMB'], 'isDynamicRam': False,
                                                'hyperVGeneration': R.choice(['1', '2']), 'osType': 'Windows' if 'windows' in p['operatingSystemDetails']['osType'] else 'Linux',
                                                'osName': p['operatingSystemDetails']['osName'],
                                                'storageContainerId': f'/subscriptions/{SUB}/resourceGroups/rg-iic-azl-prd-01/providers/Microsoft.AzureStackHCI/storageContainers/iic-azl-csv01',
                                                'protectedDisks': [{'sourceDiskId': d['uuid'], 'capacityInBytes': d['maxSizeInBytes'], 'diskFileFormat': 'VHDX'} for d in p['disks']]}}}])
else:
    # Assessments
    aproj = f'{BASE}/Microsoft.Migrate/assessmentProjects/iic-migrate-assessment'
    add('Assessment_Projects', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', 'id': aproj, 'name': 'iic-migrate-assessment', 'location': 'eastus',
                                 'properties': {'numberOfGroups': 2, 'numberOfMachines': len(machines), 'numberOfAssessments': 4, 'projectStatus': 'Active', 'provisioningState': 'Succeeded'}}])
    for m, _, _, _ in machines:
        add('Assessment_ProjectMachines', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', 'id': f"{aproj}/machines/{m['name']}", 'name': m['name'],
                                            'properties': {'displayName': m['properties']['displayName'], 'discoveryMachineArmId': m['id'], 'megabytesOfMemory': m['properties']['allocatedMemoryInMB'],
                                                           'numberOfCores': m['properties']['numberOfProcessorCore'], 'operatingSystemName': m['properties']['operatingSystemDetails']['osName']}}])

    def assessed(m, group, aname, aid):
        p = m['properties']
        support = p['productSupportStatus']['supportStatus']
        roll = R.random()
        if support == 'Unsupported' and roll < 0.55:
            suit, expl = 'ConditionallySuitable', 'GuestOperatingSystemConditionallySupported'
        elif roll < 0.04:
            suit, expl = 'NotSuitable', R.choice(['OneOrMoreDisksNotSuitable', 'NoVmSizeForSelectedAzureLocation', 'BootTypeNotSupported'])
        elif roll < 0.09:
            suit, expl = 'ReadinessUnknown', 'CheckBootType'
        else:
            suit, expl = 'Suitable', 'NotApplicable'
        cpu, memu = round(R.uniform(3, 85), 1), round(R.uniform(15, 92), 1)
        need_c = max(2, int(p['numberOfProcessorCore'] * cpu / 100 * 1.3) + 1)
        need_m = p['allocatedMemoryInMB'] / 1024 * memu / 100 * 1.3
        fit = [s for s in SIZES if s[1] >= need_c and s[2] >= need_m] or [SIZES[-1]]
        size = min(fit, key=lambda s: s[3])
        disk_gb = sum(d['maxSizeInBytes'] for d in p['disks']) / 1024 ** 3
        ok = suit in ('Suitable', 'ConditionallySuitable')
        return {'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': group, '_Assessment': aname,
                'id': f"{aid}/assessedMachines/{m['name']}", 'name': m['name'], 'type': 'Microsoft.Migrate/assessmentProjects/groups/assessments/assessedMachines',
                'properties': {'displayName': p['displayName'], 'datacenterMachineArmId': m['id'], 'operatingSystemName': p['operatingSystemDetails']['osName'],
                               'operatingSystemType': 'Windows' if 'windows' in p['operatingSystemDetails']['osType'] else 'Linux', 'bootType': R.choice(['BIOS', 'EFI']),
                               'numberOfCores': p['numberOfProcessorCore'], 'megabytesOfMemory': p['allocatedMemoryInMB'],
                               'percentageCoresUtilization': cpu, 'percentageMemoryUtilization': memu,
                               'suitability': suit, 'suitabilityExplanation': expl, 'suitabilityDetail': 'None' if suit == 'Suitable' else expl,
                               'recommendedSize': size[0] if ok else 'Unknown', 'numberOfCoresForRecommendedSize': size[1] if ok else 0,
                               'megabytesOfMemoryForRecommendedSize': size[2] * 1024 if ok else 0,
                               'monthlyComputeCostForRecommendedSize': round(size[3], 2) if ok else 0,
                               'monthlyStorageCost': round(disk_gb * 0.075, 2) if ok else 0, 'monthlyPremiumStorageCost': round(disk_gb * 0.03, 2) if ok else 0,
                               'monthlyBandwidthCost': round(R.uniform(0, 6), 2) if ok else 0,
                               'confidenceRatingInPercentage': R.choice([40, 60, 60, 80, 80, 100]), 'type': 'AssessedMachine',
                               'createdTimestamp': '2026-11-08T10:00:00Z', 'updatedTimestamp': NOW}}

    groups = [('all-servers', [m for m, _, _, _ in machines]), ('wave-1', [m for m, role, _, _ in machines if role in ('web', 'api', 'batch')][:70])]
    for gname, members in groups:
        gid = f'{aproj}/groups/{gname}'
        add('Assessment_Groups', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', 'id': gid, 'name': gname,
                                   'properties': {'machineCount': len(members), 'groupStatus': 'Completed', 'assessments': [f'{gid}/assessments/{gname}-azure-vm'], 'areAssessmentsRunning': False}}])
        aname = f'{gname}-azure-vm'
        aid = f'{gid}/assessments/{aname}'
        rows = [assessed(m, gname, aname, aid) for m in members]
        add('Assessment_AzureVM_AssessedMachines', rows)
        comp = sum(r['properties']['monthlyComputeCostForRecommendedSize'] for r in rows)
        stor = sum(r['properties']['monthlyStorageCost'] for r in rows)
        band = sum(r['properties']['monthlyBandwidthCost'] for r in rows)
        add('Assessment_AzureVM', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': gname, 'id': aid, 'name': aname,
                                    'properties': {'azureLocation': 'EastUs', 'currency': 'USD', 'sizingCriterion': 'PerformanceBased', 'azureOfferCode': 'MSAZR0003P',
                                                   'reservedInstance': 'RI3Year', 'azureHybridUseBenefit': 'Yes', 'percentile': 'Percentile95', 'timeRange': 'Week',
                                                   'scalingFactor': 1.3, 'discountPercentage': 0, 'stage': 'InProgress', 'status': 'Completed', 'numberOfMachines': len(rows),
                                                   'monthlyComputeCost': round(comp, 2), 'monthlyStorageCost': round(stor, 2), 'monthlyBandwidthCost': round(band, 2),
                                                   'confidenceRatingInPercentage': 70, 'pricesTimestamp': NOW, 'createdTimestamp': '2026-11-08T10:00:00Z', 'updatedTimestamp': NOW,
                                                   'perfDataStartTime': '2026-11-03T00:00:00Z', 'perfDataEndTime': '2026-11-10T00:00:00Z'}}])
    # AVS assessment for the VMware estate
    gid = f'{aproj}/groups/all-servers'
    avs_id = f'{gid}/avsAssessments/vmware-to-avs'
    vm_members = [m for m, _, _, k in machines if k == 'VMware']
    add('Assessment_AVS', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', 'id': avs_id, 'name': 'vmware-to-avs',
                            'properties': {'azureLocation': 'EastUs', 'currency': 'USD', 'nodeType': 'AV36P', 'numberOfNodes': 5, 'numberOfMachines': len(vm_members),
                                           'totalMonthlyCost': 41250.0, 'cpuUtilization': 61.4, 'ramUtilization': 72.9, 'storageUtilization': 48.2,
                                           'failuresToTolerateAndRaidLevel': 'Ftt1Raid1', 'memOvercommit': 1, 'vcpuOversubscription': 4, 'suitability': 'Suitable',
                                           'status': 'Completed', 'confidenceRatingInPercentage': 70, 'updatedTimestamp': NOW}}])
    for m in vm_members:
        add('Assessment_AVS_AssessedMachines', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', '_Assessment': 'vmware-to-avs',
                                                 'id': f"{avs_id}/avsAssessedMachines/{m['name']}", 'name': m['name'],
                                                 'properties': {'displayName': m['properties']['displayName'], 'datacenterMachineArmId': m['id'],
                                                                'suitability': 'Suitable' if R.random() < 0.96 else 'ConditionallySuitable', 'suitabilityExplanation': 'NotApplicable',
                                                                'numberOfCores': m['properties']['numberOfProcessorCore'], 'megabytesOfMemory': m['properties']['allocatedMemoryInMB'],
                                                                'storageInUseGB': round(R.uniform(20, 400), 1), 'operatingSystemName': m['properties']['operatingSystemDetails']['osName']}}])
    # SQL assessment
    sql_id = f'{gid}/sqlAssessments/sql-estate'
    add('Assessment_SQL', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', 'id': sql_id, 'name': 'sql-estate',
                            'properties': {'azureLocation': 'EastUs', 'currency': 'USD', 'sizingCriterion': 'PerformanceBased', 'status': 'Completed',
                                           'optimizationLogic': 'MinimizeCost', 'confidenceRatingInPercentage': 65, 'updatedTimestamp': NOW}}])
    for inst, m in sql_instances:
        target = R.choice(['AzureSqlManagedInstance', 'AzureSqlManagedInstance', 'AzureSqlDatabase', 'AzureSqlVirtualMachine'])
        suit = 'Suitable' if R.random() < 0.8 else 'ConditionallySuitable'
        cost = round(R.uniform(350, 2900), 2)
        add('Assessment_SQL_AssessedInstances', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', '_Assessment': 'sql-estate',
                                                  'id': f"{sql_id}/assessedSqlInstances/{inst['name']}", 'name': inst['name'],
                                                  'properties': {'instanceName': 'MSSQLSERVER', 'machineName': inst['properties']['hostName'], 'machineArmId': m['id'],
                                                                 'sqlEdition': inst['properties']['edition'], 'sqlVersion': inst['properties']['sqlServerVersion'],
                                                                 'numberOfCoresAllocated': inst['properties']['logicalCpuCount'], 'percentageCoresUtilization': round(R.uniform(5, 70), 1),
                                                                 'recommendedAzureSqlTargetType': target, 'recommendedSuitability': suit,
                                                                 'azureSqlMISuitabilityDetails': {'suitability': suit, 'monthlyComputeCost': cost, 'monthlyStorageCost': round(cost * 0.12, 2),
                                                                                                  'azureSqlSku': {'azureSqlServiceTier': 'GeneralPurpose', 'cores': 8}},
                                                                 'userDatabaseCount': inst['properties']['numberOfUserDatabases'], 'confidenceRatingInPercentage': 60}}])
        add('Assessment_SQL_AssessedMachines', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', '_Assessment': 'sql-estate',
                                                 'id': f"{sql_id}/assessedSqlMachines/{m['name']}", 'name': m['name'],
                                                 'properties': {'displayName': m['properties']['displayName'], 'datacenterMachineArmId': m['id'], 'suitability': suit,
                                                                'recommendedVmSize': 'Standard_E8ds_v5', 'monthlyComputeCost': round(cost * 0.8, 2), 'monthlyStorageCost': round(cost * 0.1, 2)}}])
    add('Assessment_SQL_Summaries', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_Group': 'all-servers', '_Assessment': 'sql-estate',
                                      'id': f'{sql_id}/summaries/default', 'name': 'default',
                                      'properties': {'numberOfMachines': len(sql_instances), 'numberOfSqlInstances': len(sql_instances),
                                                     'numberOfSqlDatabases': len(datasets['Discovery_Sql_Databases']), 'numberOfFciInstances': 0, 'numberOfSqlAvailabilityGroups': 0}}])
    # Business case
    bc_id = f'{aproj}/businessCases/iic-business-case'
    add('BusinessCase', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', 'id': bc_id, 'name': 'iic-business-case',
                          'properties': {'state': 'Completed', 'settings': {'azureSettings': {'targetLocation': 'eastus', 'currency': 'USD', 'discountPercentage': 0,
                                                                                              'businessCaseType': 'OptimizeForCost', 'savingsOption': 'RI3Year'}},
                                         'reportStatusDetails': [{'reportType': 'OverviewSummary', 'reportStatus': 'Completed'}]}}])
    for m, _, _, _ in machines[:120]:
        add('BusinessCase_EvaluatedMachines', [{'_Project': PROJECT, '_AssessmentProject': 'iic-migrate-assessment', '_BusinessCase': 'iic-business-case',
                                                'id': f"{bc_id}/evaluatedMachines/{m['name']}", 'name': m['name'],
                                                'properties': {'serverName': m['properties']['displayName'], 'machineId': m['id'], 'activityState': R.choice(['Active', 'Active', 'Inactive']),
                                                               'recommendedAzureTarget': R.choice(['AzureVM', 'AzureVM', 'Avs']), 'readiness': 'Ready',
                                                               'operatingSystemName': m['properties']['operatingSystemDetails']['osName'], 'supportStatus': m['properties']['productSupportStatus']['supportStatus'],
                                                               'isIdleServer': R.random() < 0.1}}])
    # Migration status
    vault = f'{BASE}/Microsoft.RecoveryServices/vaults/iic-migrate-MigrateVault-1234'
    states = [('Replicating', 'Ready to migrate'), ('Replicating', 'Ready to migrate'), ('InitialSeedingInProgress', 'Initial replication'),
              ('MigrationSucceeded', 'Migrated'), ('MigrationSucceeded', 'Migrated'), ('MigrationFailed', 'Migration failed'), ('EnableMigrationInProgress', 'Enabling')]
    for m, _, _, _ in [x for x in machines if x[1] in ('web', 'api', 'batch')][:36]:
        st, desc = R.choice(states)
        add('Migration_ReplicationMigrationItems', [{'_Project': PROJECT, '_Vault': 'iic-migrate-MigrateVault-1234',
                                                     'id': f"{vault}/replicationFabrics/f1/replicationProtectionContainers/c1/replicationMigrationItems/{m['name']}", 'name': m['name'],
                                                     'properties': {'machineName': m['properties']['displayName'], 'migrationState': st, 'migrationStateDescription': desc,
                                                                    'testMigrateState': R.choice(['None', 'TestMigrationSucceeded', 'TestMigrationSucceeded']),
                                                                    'health': 'Critical' if st == 'MigrationFailed' else 'Normal',
                                                                    'lastTestMigrationTime': '2026-11-09T18:30:00Z' if R.random() < 0.6 else None,
                                                                    'lastMigrationTime': '2026-11-10T02:15:00Z' if st == 'MigrationSucceeded' else None,
                                                                    'providerSpecificDetails': {'instanceType': 'VMwareCbt', 'targetVmSize': R.choice(SIZES)[0], 'targetLocation': 'eastus',
                                                                                                'targetResourceGroupId': f'/subscriptions/{SUB}/resourceGroups/rg-iic-wave1-prd'}}}])
# Project
pid = f'{BASE}/Microsoft.Migrate/migrateProjects/{PROJECT}'
add('Project', [{'_Project': PROJECT, 'id': pid, 'name': PROJECT, 'type': 'Microsoft.Migrate/migrateProjects', 'location': 'eastus',
                 'properties': {'provisioningState': 'Succeeded', 'registeredTools': ['ServerDiscovery', 'ServerMigration_DataReplication'] if AZL else ['ServerDiscovery', 'ServerAssessment', 'ServerMigration'], 'lastSummaryRefreshedTime': NOW}}])
for tool, purpose in [('Servers-Discovery-ServerDiscovery', 'Discovery'), ('Servers-Assessment-ServerAssessment', 'Assessment'), ('Servers-Migration-ServerMigration', 'Migration')]:
    add('Project_Solutions', [{'_Project': PROJECT, 'id': f'{pid}/solutions/{tool}', 'name': tool,
                               'properties': {'tool': tool.split('-')[-1], 'purpose': purpose, 'goal': 'Servers', 'status': 'Active',
                                              'summary': {'instanceType': 'Servers', 'discoveredCount': len(machines), 'assessedCount': len(machines), 'replicatingCount': 20, 'migratedCount': 10}}}])

# --- write, mirroring Manifest's layout ---
def flatten(obj, prefix, target, depth=0):
    if obj is None:
        if prefix: target[prefix] = ''
    elif isinstance(obj, dict):
        if depth >= 8: target[prefix] = json.dumps(obj, separators=(',', ':')); return
        for k, v in obj.items(): flatten(v, f'{prefix}.{k}' if prefix else k, target, depth + 1)
    elif isinstance(obj, list):
        simple = all(not isinstance(x, (dict, list)) for x in obj)
        target[prefix] = '' if not obj else ('; '.join(str(x) for x in obj) if simple else json.dumps(obj, separators=(',', ':')))
    else:
        target[prefix] = obj

os.makedirs(f'{OUT}/csv', exist_ok=True); os.makedirs(f'{OUT}/json', exist_ok=True)
summary = []
for name in sorted(datasets):
    recs = datasets[name]
    with open(f'{OUT}/json/{name}.json', 'w', encoding='utf-8') as f:
        json.dump(recs, f, indent=1); f.write('\n')
    rows, cols = [], []
    for r in recs:
        flat = {}; flatten(r, '', flat)
        row = {}
        for k, v in flat.items():
            short = k[11:] if k.startswith('properties.') and k[11:] not in flat else k
            row[short] = v
            if short not in cols: cols.append(short)
        rows.append(row)
    with open(f'{OUT}/csv/{name}.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
    summary.append({'Dataset': name, 'Records': len(recs), 'Status': 'OK', 'Calls': 1, 'Errors': '', 'CsvFile': f'csv/{name}.csv'})
missing_sets = (['Assessment_Projects', 'Assessment_AzureVM', 'BusinessCase', 'Discovery_HyperV_Machines', 'Migration_ReplicationMigrationItems', 'Migration_DataReplication_Jobs'] if AZL
                else ['Assessment_WebApp', 'BusinessCase_EvaluatedWebApps', 'Discovery_Imported_Machines', 'Migration_DataReplication_ProtectedItems'])
for missing in missing_sets:
    summary.append({'Dataset': missing, 'Records': 0, 'Status': 'NotAvailable', 'Calls': 1, 'Errors': '', 'CsvFile': ''})
summary.sort(key=lambda s: s['Dataset'])
with open(f'{OUT}/_Summary.csv', 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['Dataset', 'Records', 'Status', 'Calls', 'Errors', 'CsvFile']); w.writeheader(); w.writerows(summary)
with open(f'{OUT}/_Manifest.json', 'w', encoding='utf-8') as f:
    json.dump({'ExportedAtUtc': '2026-11-10T14:05:00.0000000Z', 'ScriptVersion': '1.2.1', 'SubscriptionId': SUB, 'ResourceGroup': RG, 'Project': PROJECT,
               'AuthMethod': 'Interactive', 'SignedInAs': 'pm@iic.example', 'SampleData': True,
               'Target': 'Azure Local' if AZL else 'Azure',
               'Notes': 'Fictional sample data for Infinite Improbability Corp. Generated by tools/New-SampleExport.py.', 'Datasets': summary}, f, indent=2)
    f.write('\n')
print(f'{len(machines)} machines, {len(datasets)} datasets, {sum(len(v) for v in datasets.values())} records -> {OUT}')

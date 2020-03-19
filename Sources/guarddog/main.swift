import Foundation
import Signals
import TToolkit

print(Colors.Cyan("guarddog initialized."))
print(Colors.dim("* woof *"))

class PoolWatcher {
	var zpool:ZFS.ZPool
	
	var snapshots:[ZFS.Dataset:Set<ZFS.Dataset>]
	
	init(zpool:ZFS.ZPool) throws {
		self.zpool = zpool
		
		let datasetsForPool = try zpool.listDatasets(depth:nil, types:[ZFS.DatasetType.filesystem, ZFS.DatasetType.volume])
		print(Colors.Cyan("Initializing PoolWatcher for \(zpool.name) with \(datasetsForPool.count) datasets."))
		
		snapshots = datasetsForPool.explode(using: { (nn, thisDS) -> (key:ZFS.Dataset, value:Set<ZFS.Dataset>) in
			let thisDSSnapshots = try thisDS.listDatasets(depth:1, types:[ZFS.DatasetType.snapshot])
			print(Colors.magenta("\(thisDS.name.consolidatedString()) has \(thisDSSnapshots.count)"))
			return (key:thisDS, value:thisDSSnapshots)
		})
	}
	
	func refreshDatasets() throws {
		let thisPoolsDatasets = try zpool.listDatasets(depth:nil, types:[ZFS.DatasetType.filesystem, ZFS.DatasetType.volume])
		snapshots = thisPoolsDatasets.explode(using: { (nn, thisDS) -> (key:ZFS.Dataset, value:Set<ZFS.Dataset>) in
			let thisDSSnapshots = try thisDS.listDatasets(depth:1, types:[ZFS.DatasetType.snapshot])
			return (key:thisDS, value:thisDSSnapshots)
		})
	}
}

let localshell = Host.local
let zpools = try ZFS.ZPool.all()
while true {
	let localshell = Host.local
	let zpools = try ZFS.ZPool.all()
	let watchers = zpools.explode(using: { (n, thisZpool) -> (key:ZFS.ZPool, value:PoolWatcher) in
		return (key:thisZpool, value:try PoolWatcher(zpool:thisZpool))
	})
}


struct SystemProcess:Hashable {
	var pid:UInt64
	var tty:String?
	var pcpu:Double
	var pmem:Double
	var startedOn:Date
	var user:String
	var group:String
	var command:String
	
	public static func list() throws -> Set<SystemProcess> {
		let currentHost = Host.local
		let processListCommandResult = try currentHost.runSync("ps axo pid,tty,pcpu,pmem,lstart,euser=WIDE-EUSER-COLUMN,egroup=WIDE-EGROUP-COLUMN,cmd")
		let processObjects = Set<SystemProcess>(processListCommandResult.stdout.compactMap { SystemProcess(lineData:$0) })
		return processObjects
	}
	
	/*
	expects to initialize with line data from the following command
	`ps axo pid,tty,pcpu,pmem,lstart,euser=WIDE-EUSER-COLUMN,egroup=WIDE-EGROUP-COLUMN,cmd`
	*/
	fileprivate init?(lineData:Data) {
		guard let lineAsString = String(data:lineData, encoding:.utf8) else {
			return nil
		}
		
		//we want at least 12 elements
		let columns = lineAsString.split(whereSeparator: { $0.isWhitespace })
		guard columns.count > 11 else {
			print(Colors.Red("[SystemProcess]{ INIT ERROR }\tUnable to parse data blob. At least 12 columns required to initialize a SystemProcess structure"))
			return nil
		}
		
		//initialize and parse pid
		let pidString = String(columns[0]) 
		guard let pidAsNumber = UInt64(pidString) else {
			return nil
		}
		pid = pidAsNumber
		
		//initialize and parse tty
		let ttyString = String(columns[1])
		if ttyString == "?" {
			tty = nil
		} else {
			tty = ttyString
		}
		
		//initialize and parse cpu and memory utilization metrics
		let pcpuString = String(columns[2])
		let pmemString = String(columns[3])
		guard let pcpuDouble = Double(pcpuString), let pmemDouble = Double(pmemString) else {
			return nil
		}
		pcpu = pcpuDouble
		pmem = pmemDouble
		
		//parse the date component for this process
		let dowString = String(columns[4])	//dont really need this but we capture it anyways, since it is always provided
		let monString = String(columns[5])
		let dayString = String(columns[6])
		let timeString = String(columns[7])
		let yearString = String(columns[8])
		let dateFormatter = DateFormatter()
		//need to change the format to MMM dd hh:mm:ss y if days of the month have a leading zero
		dateFormatter.dateFormat = "MMM d hh:mm:ss y"
		let fullDate = monString + " " + dayString + " " + timeString + " " + yearString
		guard let dateObject = dateFormatter.date(from:fullDate) else {
			print(Colors.Red("[SystemProcess]{ INIT ERROR }\tUnable to convert date string to date object."))
			print(Colors.dim("\(lineAsString)"))
			return nil
		}
		startedOn = dateObject
		
		//initialize and parse the effective user and group variables
		let effectiveUserString = String(columns[9])
		user = effectiveUserString
		let effectiveGroupString = String(columns[10])
		group = effectiveGroupString
		
		//initialize and parse the command
		var commandString = String(columns[11])
		for i in 12..<columns.count { 
			let stringToAppend = String(columns[i])
			commandString.append(stringToAppend)
		}
		command = commandString
	}
}

//let processes = try SystemProcess.list()
//print(processes)

//class ProcessChecker {
//	let shell:HostContext
//	let timer:TTimer
//	
//	init(_ shell:HostContext) {
//		self.shell = shell
//		self.timer = TTimer(seconds:2) { _ in
//            do {
//                let processCheck = try shell.runSync("ps axo user:20,pid,pcpu,pmem,vsz,rss,tty,stat,start,time,command")
//                if processCheck.exitCode == 0 {
//                    var lineStrings = processCheck.stdout.compactMap { String(data:$0, encoding:.utf8) }
//                    lineStrings.remove(at:0)
////                    let lineProcesses = lineStrings.compactMap { }
//                } else {
//                    print(Colors.Red("(Date()) - [SHELL][ERROR] - Unable to execute 'ps axo ...' to analyze processes"))
//                }
//            } catch _ {
//                print(Colors.Red("there was an error trying to run the shell"))
//            }
//        }
//	}
//}


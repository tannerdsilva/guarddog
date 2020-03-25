import Foundation
import Signals
import TToolkit

print(Colors.Cyan("guarddog initialized."))
print(Colors.dim("* woof *"))

let zfs_snapshotPrefix = "com-guarddog-autosnap_"

func anchoredReferenceDate() -> Date {
	let calendar = Calendar.current
	return calendar.startOfDay(for:Date())
}

let dateAnchor = anchoredReferenceDate()

class PoolWatcher:Hashable {
	var queue:DispatchQueue

	var zpool:ZFS.ZPool
	
	private var snapshots = [ZFS.Dataset:Set<ZFS.Dataset>]()
	
	var refreshTimer = TTimer(strict:true, autoRun:true, soon:true)
		
	init(zpool:ZFS.ZPool) throws {
		let defPri = Priority.`default`
		self.queue = DispatchQueue(label:"com.tannersilva.zfs-poolwatch", qos:defPri.asDispatchQoS(), target:defPri.globalConcurrentQueue)
		self.zpool = zpool
				
		try refreshDatasetsAndSnapshots()
		
		var dateTrigger:Date? = nil
		refreshTimer.anchor = dateAnchor
		refreshTimer.duration = 3
		refreshTimer.handler = { [weak self] refTimer in
			guard let self = self else {
				return
			}
			print(Colors.dim("[ PoolWatcher ] * refreshed datasets and snapshots *"))
			print("\(Date())")
			try? self.refreshDatasetsAndSnapshots()
		}
		print("Timer scheduled \(Date())")
	}
	
	func refreshDatasetsAndSnapshots() throws {
		try queue.sync {
			let thisPoolsDatasets = try zpool.listDatasets(depth:nil, types:[ZFS.DatasetType.filesystem, ZFS.DatasetType.volume])
			self.snapshots = thisPoolsDatasets.explode(using: { (nn, thisDS) -> (key:ZFS.Dataset, value:Set<ZFS.Dataset>) in
				let thisDSSnapshots = try thisDS.listDatasets(depth:1, types:[ZFS.DatasetType.snapshot])
				return (key:thisDS, value:thisDSSnapshots)
			})
		}
	}

	func fullSnapCommandDatasetMapping() -> [ZFS.SnapshotCommand:[ZFS.Dataset:Set<ZFS.Dataset>]] {
		return queue.sync {
			var buildData = [ZFS.SnapshotCommand:Set<ZFS.Dataset>]()
		
			func insert(snap:ZFS.SnapshotCommand, forDataset dataset:ZFS.Dataset) {
				if var existingDatasets = buildData[snap] {
					existingDatasets.update(with:dataset)
				} else {
					buildData[snap] = Set<ZFS.Dataset>([dataset])
				}
			}
		
			snapshots.keys.explode(using: { (n, k) -> (key:ZFS.Dataset, value:Set<ZFS.SnapshotCommand>)? in
				if let hasSnapshotCommands = k.snapshotCommands {
					return (key:k, value:hasSnapshotCommands) 
				}
				return nil
			}, merge: { (n, kv) -> Void in
				for (_, curSnap) in kv.value.enumerated() {
					insert(snap:curSnap, forDataset:kv.key)
				}
			})
			
			return buildData.explode(using: { (n, kv) -> (key:ZFS.SnapshotCommand, value:[ZFS.Dataset:Set<ZFS.Dataset>]) in
				var datasetSnapshots = [ZFS.Dataset:Set<ZFS.Dataset>]()
				for (_, curDataset) in kv.value.enumerated() {
					if let hasSnapshots = self.snapshots[curDataset] {
						datasetSnapshots[curDataset] = hasSnapshots
					}
				}
				return (key:kv.key, value:datasetSnapshots)
			})
		}
	}
	
	public func hash(into hasher:inout Hasher) {
		hasher.combine(zpool)
	}
	
	public static func == (lhs:PoolWatcher, rhs:PoolWatcher) -> Bool {
		return lhs.zpool == rhs.zpool
	}
}


extension Collection where Element == ZFS.Dataset {
	/*
		This function is used to help determine if a collection of snapshots are due for a new snapshot event with a snapshot command given as input
		This function will return nil if there is no existing snapshots to derive this data from
	*/
	func nextSnapshotDate(with command:ZFS.SnapshotCommand) -> Date? {
		var latestDate:Date? = nil
		for (_, curSnapshot) in enumerated() {
			if latestDate == nil || curSnapshot.creation > latestDate! {
				latestDate = curSnapshot.creation
			}
		}
		guard let gotLatestDate = latestDate else {
			return nil
		}
		let now = Date()
		let latestSnapshotAbsolute = gotLatestDate.timeIntervalSince1970
		let nextSnapEvent = Date(timeIntervalSince1970:latestSnapshotAbsolute + command.secondsInterval)
		return nextSnapEvent
	}
}
//class ZFSSnapper {
//	let priority:Priority
//	let queue:DispatchQueue
//
//	var snapshotPrefix = zfs_snapshotPrefix
//
//	var poolwatchers:Set<PoolWatcher>
//
//	var snapshotCommands:[ZFS.SnapshotCommand:Set<ZFS.Dataset>]
//
//	var snapshotTimers = [TTimer]()
//
//	init() throws {
//		self.priority = Priority.`default`
//		self.queue = DispatchQueue(label:"com.tannersilva.instance.zfs-snapper", qos:priority.asDispatchQoS())
//		let zpools = try ZFS.ZPool.all()
//		let watchers = zpools.explode(using: { (n, thisZpool) -> (key:ZFS.ZPool, value:PoolWatcher) in
//			return (key:thisZpool, value:try PoolWatcher(zpool:thisZpool))
//		})
//		poolwatchers = Set(watchers.values)
//	}
//
//
//	func fullReschedule() throws {
//		queue.sync {
//			//invalidate all existing timers
//			for (_, curTimer) in snapshotTimers.enumerated() {
//				curTimer.cancel()
//			}
//		
//			//remove all timers
//			snapshotTimers.removeAll()
//		
//			poolwatchers.explode(using: { (n, curwatcher) -> [ZFS.SnapshotCommand:[ZFS.Dataset:Set<ZFS.Dataset>]] in
//				let frequenciesAndDatasets = curwatcher.fullSnapCommandDatasetMapping()
//				return frequenciesAndDatasets
//			}, merge: { (n, frequencyAndDatasets) in
//				let snapshotCommand = frequencyAndDatasets.key
//				for (_, curKv) in frequencyAndDatasets.value.enumerated() {
//					let datasetInQuestion = curKv.key
//					let snapshotsForDataset = curKv.value
//					let nextSnapshotDate = snapshotsForDataset.nextSnapshotDate(with:snapshotCommand)
//					let newTimer = TTimer(strict:true, autoRun:true)
//					newTimer.anchor = dateAnchor
//					newTimer.duration = 
//				}
//			})
//		}		
//	}
//}

func loadPoolWatchers() throws -> [ZFS.ZPool:PoolWatcher] {
	let localshell = Host.local
	let zpools = try ZFS.ZPool.all()
	let watchers = zpools.explode(using: { (n, thisZpool) -> (key:ZFS.ZPool, value:PoolWatcher) in
		return (key:thisZpool, value:try PoolWatcher(zpool:thisZpool))
	})
	return watchers
}

let runSemaphore = DispatchSemaphore(value:0)

let poolWatchers = try loadPoolWatchers()

Signals.trap(signal:.int) { signal in
	runSemaphore.signal()
}

runSemaphore.wait()

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
		guard columns.count >= 12 else {
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


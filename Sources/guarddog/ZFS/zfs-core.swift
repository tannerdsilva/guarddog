import TToolkit
import Foundation

//public enum DataSize {
//	case zettabytes(Double)
//	case exabytes(Double)
//	case petabytes(Double)
//	case terabytes(Double)
//	case gigabytes(Double)
//	case megabytes(Double)
//	case kilobytes(Double)
//	case bytes(Int)
//	
//	public static func fromZFSSizeString(_ sizeString:String) -> DataSize? {
//		var sizeStringToModify = sizeString
//		let lastCharacter = sizeStringToModify.removeLast()
//        guard let sizeAsDouble = Double(sizeStringToModify) else {
//        	print(Colors.red("This is not a double value: \(sizeStringToModify)"))
//            return nil
//        }
//        switch lastCharacter {
//            case "Z", "z":
//                return .zettabytes(sizeAsDouble)
//            case "E", "e":
//                return .exabytes(sizeAsDouble)
//            case "P", "p":
//                return .petabytes(sizeAsDouble)
//            case "T", "t":
//                return .terabytes(sizeAsDouble)
//            case "G", "g":
//                return .gigabytes(sizeAsDouble)
//            case "M", "m":
//                return .megabytes(sizeAsDouble)
//            case "K", "k":
//                return .kilobytes(sizeAsDouble)
//            case "B", "b":
//                return .bytes(Int(sizeAsDouble))
//            default:
//                return nil
//        }
//	}
//}

extension String {
    fileprivate func parsePercentage() -> Double? {
        guard let doubleConverted = Double(self) else {
            return nil
        }
        return doubleConverted / 100
    }
    
    fileprivate func parseMultiplier() -> Double? {
        guard let doubleConverted = Double(self) else {
            return nil
        }
        return doubleConverted
    }
    
    fileprivate func parseSize() -> BInt? {
		return BInt(self)
    }
}

public class ZFS {
	/*
	SnapshotFrequency is used to specify a duration of time which a dataset is supposed to be snapshotted
	*/
	public enum SnapshotFrequency:UInt8 {
		case month = 1
		case day = 2
		case hour = 3
		case minute = 4
		case seconds = 5
		
		/*
		This will convert a given SnapshotFrequency variable to an explicit duration value in seconds
		*/
		public func secondsInterval(units:Double) -> Double {
			switch self {
				case .month:
				return units * 2629800
				case .day:
				return units * 86400
				case .hour:
				return units * 3600
				case .minute:
				return units * 60
				case .seconds:
				return units
			}
		}
		
		/*
		=======================================================================
		This function parses a human-written shapshot frequency command.
		This is an example of a snapshot frequency command:
		=======================================================================
		24h		-	Every 24 hours
		0.5h	-	Every half hour
		30m		-	Every half hour
		0.75s	-	Every 75 milliseconds
		=======================================================================
		There are two elements to a snapshot frequency command:
			-	frequency: what is the base unit that we are using to represent a given duration in time?
			-	value: what is the value of this base unit? (example of a base unit: *24* is the value in *24 hours*)
		=======================================================================
		*/
		fileprivate static func parse(_ humanCommand:String) -> (value:Double, freq:SnapshotFrequency)? {
			var valueString = ""
			var typeString = ""
			for (_, curChar) in humanCommand.enumerated() {
				if curChar.isNumber == true || curChar == "." {
					valueString.append(curChar)
				} else if curChar.isLetter == true {
					typeString.append(curChar)
				} else {
					return nil
				}
			}
			print(Colors.cyan("[ VALUE ]( \(valueString) )"))
			print(Colors.yellow("[ TYPE ]( \(typeString) )"))
			if let parsedValue = Double(valueString), let snapFreq = SnapshotFrequency(typeString) {
				return (value:parsedValue, freq:snapFreq)
			} else {
				return nil
			}
		}
		
		/*
		========================================================================
		Note: Presumably this initializer would get called by another function that is able to separate the value from the frequency description
		========================================================================
		This initializer takes a string that describes (in as few characters as possible) the frequency needed for the variable
		========================================================================
		*/
		public init?<T>(_ descriptionString:T) where T:StringProtocol {
			switch descriptionString.lowercased() {
				case "mo":
					self = .month
				case "d":
					self = .day
				case "h":
					self = .hour
				case "m", "mi":
					self = .minute
				case "s":
					self = .seconds
				default:
					return nil
			}
		}
	}
	
	/*
	===============================================================================
	A snapshot command is made of a frequency and the units for that frequency.
	The keep value is the maximum number of snapshots that are to be retained
	===============================================================================
	Example: A SnapshotCommand that triggers a snapshot every 2.5 seconds
	-------------------------------------------------------------------------------
		- frequency = .seconds
		- units = 2.5
		- keep	= 45
	-------------------------------------------------------------------------------
	Written as a human: "2.5s:45"
	===============================================================================
	*/
	public struct SnapshotCommand:Hashable {
		var frequency:SnapshotFrequency
		var units:Double
		var keep:UInt?
		
		//parses a string containing multiple snapshot commands, separated by a comma
		public static func parse(_ commands:String) -> Set<SnapshotCommand> {
			let subcommands = commands.split(separator:",")
			var snapCommands = Set<SnapshotCommand>()
			for (_, curSnapshotCommand) in subcommands.enumerated() {
				if let didConvertToCommand = SnapshotCommand(curSnapshotCommand) {
					_ = snapCommands.update(with:didConvertToCommand)
				}
			}
			return snapCommands
		}
		
		//create a snapshot command with explicit values
		public init(frequency:SnapshotFrequency, units:Double) {
			self.frequency = frequency
			self.units = units
		}
		
		//try to parse a single snapshot command
		public init?<T>(_ singleCommand:T) where T:StringProtocol {
			guard singleCommand != "-" else {
				return nil
			}
			
			let commandBreakdown = singleCommand.split(separator:":")
			switch commandBreakdown.count {
				case 1:
				let firstString = String(commandBreakdown[0])
				guard	let frequencyCommand = SnapshotFrequency.parse(firstString) else {
					return nil		
				}
				keep = nil
				units = frequencyCommand.value
				frequency = frequencyCommand.freq
				
				case 2:
				let firstString = String(commandBreakdown[0])
				let secondString = String(commandBreakdown[1])
				guard	let parsedKeep = UInt(secondString),
						let frequencyCommand = SnapshotFrequency.parse(firstString) else { 
					return nil
				}
				keep = parsedKeep
				units = frequencyCommand.value
				frequency = frequencyCommand.freq
					
				default:
				return nil
			}
		}
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(frequency)
			hasher.combine(units)
			if let hasKeepValue = keep {
				hasher.combine(hasKeepValue)
			}
		}
	}
	
	/*
	==============================================================
	In ZFS, a dataset can have four types.
	==============================================================
		1. Filesystem: traditional filesystem structure with files and directories. Mounts to a mountpoint
		2. Volume: block storage device that typically can be found in /dev/zvol/
		3. Snapshot: If you dont know what zfs snapshots are, then I dont even know how you found this library in the first place
		4. Bookmarks: Markers that are assigned to snapshots. Helpful for tracking states (or 'heads') of snapshots
	==============================================================
	*/
	public enum DatasetType:UInt8 {
		case filesystem
		case volume
		case snapshot
		case bookmark
		
		init?(_ input:String) {
			switch input.lowercased() {
				case "filesystem":
				self = .filesystem
				
				case "volume":
				self = .volume
				
				case "snapshot":
				self = .snapshot
				
				case "bookmark":
				self = .bookmark
				
				default:
				return nil
			}
		}
	}
	
	
	/*
	===========================================================
	The health enum is used to describe the state of a zpool
	===========================================================
	*/
	public enum Health:UInt8 {
		case degraded = 0
        case faulted = 1
        case offline = 2
        case online = 3
        case removed = 4
        case unavailable = 5
        
        init?(description:String) {
            switch description {
            case "DEGRADED":
                self = .degraded
            case "FAULTED":
                self = .faulted
            case "OFFLINE":
                self = .offline
            case "ONLINE":
                self = .online
            case "REMOVED":
                self = .removed
            case "UNAVAIL":
                self = .unavailable
            default:
                return nil
            }
        }
	}
		
	public struct Dataset:Hashable {
		fileprivate static let listCommand = "zfs list -p -H -o guid,type,name,creation,reservation,refer,used,available,quota,refquota,volsize,com.guarddog:auto-snapshot"
		
		public var type:DatasetType
		
		public var guid:String
		
		public var name:String
		public var namePath:[String]
		
		public var zpool:ZPool
		
		public let creation:Date
		
		public let reserved:BInt
		
		public let refer:BInt
		public let used:BInt
		public let free:BInt
		
		public let quota:BInt
		public let refQuota:BInt
		
		public let volumeSize:BInt?	// should be nil where type != .volume 
		
		public let snapshotCommands:Set<SnapshotCommand>?
		
		/*
		meant to initialize with data from the following command
		zfs list -p -H -o guid,type,name,creation,reservation,refer,used,available,quota,refquota,volsize,com.guarddog:auto-snapshot
		*/
		fileprivate init?(zpool:ZPool, _ lineData:Data) {
			guard let asString = String(data:lineData, encoding:.utf8) else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to convert input data blob to string with UTF-8 encoding."))
				return nil
			}
			let dsColumns = asString.split(whereSeparator: { $0.isWhitespace })
			guard dsColumns.count == 12 else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to convert input data to columns. There must be 10 columns"))
				return nil
			}
			
			guid = String(dsColumns[0])
			
			let typeString = String(dsColumns[1])
			guard let parsedType = DatasetType(typeString) else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to parse the parse of this dataset. Parse string given: \(typeString)"))
				return nil
			}
			self.zpool = zpool
			type = parsedType
			
			name = String(dsColumns[2])
			namePath = name.split(separator:"/").compactMap({ String($0) })
			
			let creationString = String(dsColumns[3])
			guard let creationDouble = Double(creationString) else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to convert the creation date of this dataset to a valid date object."))
				return nil
			}
			creation = Date(timeIntervalSince1970:creationDouble)

			let reservString = String(dsColumns[4]) 	// might not be specified (0 when no value is given)
			let referString = String(dsColumns[5])		// guaranteed
			let usedString = String(dsColumns[6])		// guaranteed
			let availString = String(dsColumns[7])		// guaranteed
			let quotaString = String(dsColumns[8])		// might not be specified (0 when no value is given)
			let refQuotaString = String(dsColumns[9])	// might not be specified (0 when no value is given) 

			guard	let parsedReserve = BInt(reservString),
					let parsedRefer = BInt(referString),
					let parsedUsed = BInt(usedString),
					let parsedAvail = BInt(availString),
					let parsedQuota = BInt(quotaString),
					let parsedRefQuota = BInt(refQuotaString) else {
				return nil
			}
			reserved = parsedReserve
			refer = parsedRefer
			used = parsedUsed
			free = parsedAvail
			quota = parsedQuota
			refQuota = parsedRefQuota
			
			let volSizeString = String(dsColumns[10])	// might not be specified (- when no value is specified)
			if volSizeString == "-" {
				volumeSize = nil
			} else {
				guard let parsedVolSize = BInt(volSizeString) else {
					print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to parse the volume size of this dataset. String given: \(volSizeString)"))
					return nil
				}
				volumeSize = parsedVolSize
			}
			
			let sscString = String(dsColumns[11]) // might not be specified ('-' when no value is given)
			if sscString == "-" {
				snapshotCommands = nil
			} else {
				snapshotCommands = SnapshotCommand.parse(sscString)
			}
		}
	}
	
	public struct ZPool:Hashable {
		fileprivate static let listCommand = "zpool list -p -H"
		
		public let name:String
		
		public let volume:BInt
		public let allocated:BInt
		public let free:BInt
		
		public let frag:Double
		public let cap:Double
        
        public let dedup:Double
		
		public let health:Health
        
        public let altroot:URL?
		
		//runs a shell command to list all available ZFS pools, returns a set of ZPool objects
		public static func all() throws -> Set<ZPool> {
			let currentHost = Host.local
			let runResult = try currentHost.runSync(Self.listCommand)
			if runResult.succeeded == false {
				return Set<ZPool>()
			} else {
				return Set(runResult.stdout.compactMap { ZPool($0) })
			}
		}

		fileprivate init?(_ lineData:Data) {
            guard let asString = String(data:lineData, encoding:.utf8) else {
                print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to convert data blob to string with UTF-8 encoding."))
                return nil
            }
			let poolElements = asString.split(whereSeparator: { $0.isWhitespace })
			guard poolElements.count == 10 else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to create zpool structure because incorrect data was sent to this function."))
				return nil
			}
			name = String(poolElements[0])
			let sizeString = String(poolElements[1])
			let allocString = String(poolElements[2])
			let freeString = String(poolElements[3])
			//expandsz (index 4) is not stored. idgaf
			let fragString = String(poolElements[5])
			let capString = String(poolElements[6])
			let dedupString = String(poolElements[7])
			let healthString = String(poolElements[8])
            let altrootString = String(poolElements[9])
            
            //parse the primary variables
            guard	let convertedSize = BInt(sizeString),
            		let convertedAlloc = BInt(allocString),
            		let convertedFree = BInt(freeString),
            		let fragPercent = fragString.parsePercentage(),
            		let capacityPercent = capString.parsePercentage(),
            		let dedupMultiplier = dedupString.parseMultiplier(),
            		let healthObject = ZFS.Health(description:healthString) else {
            	return nil		
        	}

            volume = convertedSize
            allocated = convertedAlloc
            free = convertedFree
            
            frag = fragPercent
            cap = capacityPercent
            
            dedup = dedupMultiplier
            
            health = healthObject
            
            if altrootString == "-" || altrootString.contains("/") == false {
                altroot = nil
            } else {
                altroot = URL(fileURLWithPath:altrootString)
            }
		}
		
		public func listDatasets() throws -> Set<Dataset> {
			return try listDatasets(depth:1)
		}
		
		public func listDatasets(depth:UInt) throws -> Set<Dataset> {
			let currentHost = Host.local
			var shellCommand = Dataset.listCommand + " -d " + String(depth) + " " + name
			let datasetList = try currentHost.runSync(shellCommand)
			let datasets = Set(datasetList.stdout.compactMap({ Dataset(zpool:self, $0) }))
			return datasets
		}
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(name)
		}
        
        public static func == (lhs:ZPool, rhs:ZPool) -> Bool {
            return lhs.name == rhs.name
        }
	}
}

/*
== zpool status flags

-g Display vdev GUIDs instead of normal device names
-L Display real paths for vdevs. resolve all symbolic links
-P display full paths of the vdevs instead of only the last component of the path
-T u|d display a time stamp (u for internal date rep, d for standardized date rep
-v display verbose data error information
-x only display status for bools that are exhibiting errors that are otherwise unavailable

sudo zfs list -p -o available,used,refer,volsize
== dataset native properties
The following properties are supported:

	PROPERTY       EDIT  INHERIT   VALUES

	available        NO       NO   <size>
	clones           NO       NO   <dataset>[,...]
	compressratio    NO       NO   <1.00x or higher if compressed>
	createtxg        NO       NO   <uint64>
	creation         NO       NO   <date>
	defer_destroy    NO       NO   yes | no
	filesystem_count  NO       NO   <count>
	guid             NO       NO   <uint64>
	logicalreferenced  NO       NO   <size>
	logicalused      NO       NO   <size>
	mounted          NO       NO   yes | no
	origin           NO       NO   <snapshot>
	receive_resume_token  NO       NO   <string token>
	refcompressratio  NO       NO   <1.00x or higher if compressed>
	referenced       NO       NO   <size>
	snapshot_count   NO       NO   <count>
	type             NO       NO   filesystem | volume | snapshot | bookmark
	used             NO       NO   <size>
	usedbychildren   NO       NO   <size>
	usedbydataset    NO       NO   <size>
	usedbyrefreservation  NO       NO   <size>
	usedbysnapshots  NO       NO   <size>
	userrefs         NO       NO   <count>
	written          NO       NO   <size>
	aclinherit      YES      YES   discard | noallow | restricted | passthrough | passthrough-x
	acltype         YES      YES   noacl | posixacl
	atime           YES      YES   on | off
	canmount        YES       NO   on | off | noauto
	casesensitivity  NO      YES   sensitive | insensitive | mixed
	checksum        YES      YES   on | off | fletcher2 | fletcher4 | sha256 | sha512 | skein | edonr
	compression     YES      YES   on | off | lzjb | gzip | gzip-[1-9] | zle | lz4
	context         YES       NO   <selinux context>
	copies          YES      YES   1 | 2 | 3
	dedup           YES      YES   on | off | verify | sha256[,verify], sha512[,verify], skein[,verify], edonr,verify
	defcontext      YES       NO   <selinux defcontext>
	devices         YES      YES   on | off
	dnodesize       YES      YES   legacy | auto | 1k | 2k | 4k | 8k | 16k
	exec            YES      YES   on | off
	filesystem_limit YES       NO   <count> | none
	fscontext       YES       NO   <selinux fscontext>
	logbias         YES      YES   latency | throughput
	mlslabel        YES      YES   <sensitivity label>
	mountpoint      YES      YES   <path> | legacy | none
	nbmand          YES      YES   on | off
	normalization    NO      YES   none | formC | formD | formKC | formKD
	overlay         YES      YES   on | off
	primarycache    YES      YES   all | none | metadata
	quota           YES       NO   <size> | none
	readonly        YES      YES   on | off
	recordsize      YES      YES   512 to 1M, power of 2
	redundant_metadata YES      YES   all | most
	refquota        YES       NO   <size> | none
	refreservation  YES       NO   <size> | none
	relatime        YES      YES   on | off
	reservation     YES       NO   <size> | none
	rootcontext     YES       NO   <selinux rootcontext>
	secondarycache  YES      YES   all | none | metadata
	setuid          YES      YES   on | off
	sharenfs        YES      YES   on | off | share(1M) options
	sharesmb        YES      YES   on | off | sharemgr(1M) options
	snapdev         YES      YES   hidden | visible
	snapdir         YES      YES   hidden | visible
	snapshot_limit  YES       NO   <count> | none
	sync            YES      YES   standard | always | disabled
	utf8only         NO      YES   on | off
	version         YES       NO   1 | 2 | 3 | 4 | 5 | current
	volblocksize     NO      YES   512 to 128k, power of 2
	volmode         YES      YES   default | full | geom | dev | none
	volsize         YES       NO   <size>
	vscan           YES      YES   on | off
	xattr           YES      YES   on | off | dir | sa
	zoned           YES      YES   on | off
	userused@...     NO       NO   <size>
	groupused@...    NO       NO   <size>
	userquota@...   YES       NO   <size> | none
	groupquota@...  YES       NO   <size> | none
	written@<snap>   NO       NO   <size>
*/

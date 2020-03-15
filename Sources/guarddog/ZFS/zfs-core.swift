import TToolkit
import Foundation

public enum DataSize {
	case zettabytes(Double)
	case exabytes(Double)
	case petabytes(Double)
	case terabytes(Double)
	case gigabytes(Double)
	case megabytes(Double)
	case kilobytes(Double)
	case bytes(Int)
	
	public static func fromZFSSizeString(_ sizeString:String) -> DataSize? {
		var sizeStringToModify = sizeString
		let lastCharacter = sizeStringToModify.removeLast()
        guard let sizeAsDouble = Double(sizeString) else {
            return nil
        }
        switch lastCharacter {
            case "Z", "z":
                return .zettabytes(sizeAsDouble)
            case "E", "e":
                return .exabytes(sizeAsDouble)
            case "P", "p":
                return .petabytes(sizeAsDouble)
            case "T", "t":
                return .terabytes(sizeAsDouble)
            case "G", "g":
                return .gigabytes(sizeAsDouble)
            case "M", "m":
                return .megabytes(sizeAsDouble)
            case "K", "k":
                return .kilobytes(sizeAsDouble)
            case "B", "b":
                return .bytes(Int(sizeAsDouble))
            default:
                return nil
        }
	}
}

extension String {
    fileprivate func parsePercentage() -> Double? {
        var stringToModify = self
        let lastCharacter = stringToModify.removeLast()
        guard let doubleConverted = Double(stringToModify), lastCharacter == "%" else {
            return nil
        }
        return doubleConverted / 100
    }
    
    fileprivate func parseMultiplier() -> Double? {
        var stringToModify = self
        let lastCharacter = stringToModify.removeLast()
        guard let doubleConverted = Double(stringToModify), lastCharacter == "x" else {
            return nil
        }
        return doubleConverted
    }
}


public class ZFS {
	public enum ZFSError: Error {
		case invalidData
	}
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
	
	public struct ZPool:Hashable {
		let name:String
		let volume:DataSize
		let allocated:DataSize
		let free:DataSize
		
		let frag:Double
		let cap:Double
        
        let dedup:Double
		
		let health:Health
        
        let altroot:URL?
		
		init(_ lineData:Data) throws {
            guard let asString = String(data:lineData, encoding:.utf8) else {
                print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to convert data blob to string with UTF-8 encoding."))
                throw ZFSError.invalidData
            }
            print(Colors.magenta("\(asString)"))
			let poolElements = asString.split(whereSeparator: {
                return $0.isWhitespace
            })
            print(Colors.dim("\(poolElements)"))
			guard poolElements.count == 10 else {
				print(Colors.Red("[ ZFS ]{ ERROR }\tUnable to create zpool structure because incorrect data was sent to this function."))
				throw ZFSError.invalidData
			}
			name = String(poolElements[0])
			print(Colors.yellow("zpool identified: \(poolElements[0])"))
			let sizeString = String(poolElements[1])
			let allocString = String(poolElements[2])
			let freeString = String(poolElements[3])
			//expandsz (index 4) is not stored. idgaf
			let fragString = String(poolElements[5])
			let capString = String(poolElements[6])
			let dedupString = String(poolElements[7])
			let healthString = String(poolElements[8])
            let altrootString = String(poolElements[9])
            
            //parse the relevant variables
            guard   let convertedSize = DataSize.fromZFSSizeString(sizeString) else {
            	print(Colors.red("[ ZFS ]{ size }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let convertedAlloc = DataSize.fromZFSSizeString(allocString) else {
            	print(Colors.red("[ ZFS ]{ alloc }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let convertedFree = DataSize.fromZFSSizeString(freeString) else {
            	print(Colors.red("[ ZFS ]{ free }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let fragPercent = fragString.parsePercentage() else {
            	print(Colors.red("[ ZFS ]{ frag% }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let capacityPercent = capString.parsePercentage() else {
            	print(Colors.red("[ ZFS ]{ cap% }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let dedupMultiplier = dedupString.parseMultiplier() else {
            	print(Colors.red("[ ZFS ]{ dedupX }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            guard	let parsedHealth = ZFS.Health(description:healthString) else {
            	print(Colors.red("[ ZFS ]{ health }\tUnable to parse."))
                throw ZFSError.invalidData
            }
            
            volume = convertedSize
            allocated = convertedAlloc
            free = convertedFree
            
            frag = fragPercent
            cap = capacityPercent
            
            dedup = dedupMultiplier
            
            health = parsedHealth
            
            if altrootString == "-" || altrootString.contains("/") == false {
                altroot = nil
            } else {
                altroot = URL(fileURLWithPath:altrootString)
            }
		}
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(name)
		}
        
        public static func == (lhs:ZPool, rhs:ZPool) -> Bool {
            return lhs.name == rhs.name
        }
		
		//runs a shell command to list all available ZFS pools, returns a set of ZPool objects
		public static func all() throws -> Set<ZPool> {
			let currentHost = Host.local
			let runResult = try currentHost.runSync("zpool list -H")
			if runResult.succeeded == false {
				return Set<ZPool>()
			} else {
				return Set(runResult.stdout.compactMap { try? ZPool($0) })
			}
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

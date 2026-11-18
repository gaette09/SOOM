import XCTest
import SwiftUI
import UIKit
import CryptoKit
@testable import SOOM

@MainActor final class PhotoHostClipProductRegressionTests: XCTestCase {
    private func safeSyntheticHost() -> Bool {
        guard ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
              ProcessInfo.processInfo.environment["SOOM_SKELETON_QA"] == "1",
              ProcessInfo.processInfo.environment["SOOM_SKELETON_STYLE"] == "value",
              ReviewDemoMode.isActive, ReviewDemoController.shared.runtime != nil else {
            XCTFail("Explicit isolated synthetic app-host configuration required"); return false
        }
        let currentKeys = ["SOOMSupabaseURL", "SOOMSupabaseAnonKey"]
        let legacyKeys = ["SOOM_SUPABASE_URL", "SOOM_SUPABASE_ANON_KEY"]
        guard currentKeys.allSatisfy({ (Bundle.main.object(forInfoDictionaryKey: $0) as? String) == "" }),
              legacyKeys.allSatisfy({ key in
                  guard let value = Bundle.main.object(forInfoDictionaryKey: key) else { return true }
                  return (value as? String) == ""
              }) else {
            XCTFail("Current service keys must be empty strings; legacy keys must be absent or empty strings"); return false
        }
        let environment = AuthEnvironmentLoader().load()
        guard environment.supabaseURL == nil, environment.supabaseAnonKey == nil,
              !environment.isSupabaseConfigured,
              !SupabaseAuthConfiguration.from(environment: environment).isConfigured else {
            XCTFail("Loaded host service configuration must be empty"); return false
        }
        guard SupabaseClientProvider(environment: environment).makeClient() == nil else {
            XCTFail("Configured real client is not permitted"); return false
        }
        return true
    }
    private enum Failure: Error { case readiness, unstable, containment, render, missingPresentation }
    private func rect(_ x: CGRect) -> [Double] { [Double(x.minX), Double(x.minY), Double(x.width), Double(x.height)] }
    private func transform(_ t: CATransform3D) -> [Double] {
        [t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44].map(Double.init)
    }
    private func layer(_ l: CALayer) -> [String: Any] {
        ["frame":rect(l.frame),"bounds":rect(l.bounds),"position":[Double(l.position.x),Double(l.position.y)],
         "anchorPoint":[Double(l.anchorPoint.x),Double(l.anchorPoint.y)],"transform":transform(l.transform),
         "masksToBounds":l.masksToBounds,"hasMask":l.mask != nil,"opacity":Double(l.opacity)]
    }
    private func presentationViewport(_ view: UIView, root: UIView) -> [Double]? {
        guard let from=view.layer.presentation(),let to=root.layer.presentation() else{return nil}
        return rect(from.convert(from.bounds,to:to))
    }
    private func image(_ view: UIView) throws -> UIImage {
        guard view.bounds.width > 0, view.bounds.height > 0 else { throw Failure.render }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        var rendered = false
        let result = UIGraphicsImageRenderer(size:view.bounds.size,format:f).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:view.bounds.size))
            rendered = view.drawHierarchy(in:CGRect(origin:.zero,size:view.bounds.size),afterScreenUpdates:true)
        }
        guard rendered else { throw Failure.render }; return result
    }
    private func colors(_ image: UIImage, probes: [String: [Int]] = [:]) throws -> [String: Any] {
        let cg = try XCTUnwrap(image.cgImage), w = cg.width, h = cg.height
        var bytes = [UInt8](repeating:0,count:w*h*4)
        try bytes.withUnsafeMutableBytes { buffer in
            let c = try XCTUnwrap(CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            c.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        }
        func label(_ i: Int) -> Int? {
            let r=bytes[i],g=bytes[i+1],b=bytes[i+2]
            if r>200 && g<60 && b<60 { return 0 }
            if r<60 && g>200 && b<60 { return 1 }
            if r<60 && g<60 && b>200 { return 2 }
            return nil
        }
        var counts=[0,0,0], minX=[w,w,w], maxX=[-1,-1,-1], centerRows=[[Int]](repeating:[],count:3)
        for y in 0..<h { for x in 0..<w {
            if let k=label((y*w+x)*4) { counts[k]+=1;minX[k]=min(minX[k],x);maxX[k]=max(maxX[k],x);if y==h/2 {centerRows[k].append(x)} }
        } }
        let names=["red","green","blue"]
        var result:[String:Any]=["width":w,"height":h,"canonical":"DeviceRGB RGBA8 premultipliedLast byteOrder32Big","threshold":"dominant>200 others<60","centerClass":label(((h/2)*w+w/2)*4).map {names[$0]} ?? "other", "sourceBitsPerComponent":cg.bitsPerComponent,"sourceBitsPerPixel":cg.bitsPerPixel,"sourceColorSpace":cg.colorSpace?.name as String? ?? "unknown","sourceUIImageScale":Double(image.scale)]
        for k in 0..<3 { result[names[k]]=["pixels":counts[k],"minX":maxX[k]<0 ? -1:minX[k],"maxX":maxX[k],"centerRowXs":centerRows[k]] }
        result["corner2RGBA"]=Array(bytes[(2*w+2)*4..<(2*w+2)*4+4]).map(Int.init)
        result["corner2Class"]=label((2*w+2)*4).map {names[$0]} ?? "other"
        result["topCenter2Class"]=label((2*w+w/2)*4).map {names[$0]} ?? "other"
        if !probes.isEmpty {
            var measured=[String:Any]()
            for (name,xy) in probes {
                guard xy.count==2,xy[0]>=0,xy[0]<w,xy[1]>=0,xy[1]<h else {throw Failure.render}
                let offset=(xy[1]*w+xy[0])*4
                measured[name]=["xy":xy,"rgba":Array(bytes[offset..<offset+4]).map(Int.init),"class":label(offset).map{names[$0]} ?? "other"]
            }
            result["probes"]=measured
            result["probeCoordinates"]="canonical CGContext RGBA8 bitmap column/row indices"
        }
        return result
    }
    private func pager(_ controller: UIViewController) -> WorkoutMediaPagerController? {
        if let p=controller as? WorkoutMediaPagerController { return p }
        return controller.children.lazy.compactMap { self.pager($0) }.first
    }
    private func pageHosts(_ pager: WorkoutMediaPagerController, _ scroll: UIScrollView) -> [UIHostingController<AnyView>] {
        pager.children.compactMap {$0 as? UIHostingController<AnyView>}.filter {$0.view.superview === scroll}.sorted {$0.view.frame.minX < $1.view.frame.minX}
    }
    private func attach(_ image: UIImage, name: String) {
        let a=XCTAttachment(image:image);a.name=name;a.lifetime = .keepAlways;add(a)
    }
    private func json(_ value: [String:Any], name: String) throws {
        let d=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]);let a=XCTAttachment(data:d,uniformTypeIdentifier:"public.json");a.name=name;a.lifetime = .keepAlways;add(a)
    }
    private struct Fixture {
        let references: [WorkoutPhotoReference]
        let images: [UIImage]
        let evidence: [String: Any]
    }
    private func fixture() async throws -> Fixture {
        let runtime=try XCTUnwrap(ReviewDemoController.shared.runtime)
        let store=SwiftDataUnifiedWorkoutStore(modelContext:runtime.storage.container.mainContext)
        let recent=try await store.fetchRecentWorkouts(days:90),workout=try XCTUnwrap(recent.first)
        let sizes=[CGSize(width:600,height:900),CGSize(width:500,height:1000),CGSize(width:1400,height:600)]
        let fills:[UIColor]=[.red,.green,.blue]
        let drafts=try sizes.enumerated().map { i,size in
            let f=UIGraphicsImageRendererFormat();f.scale=1
            let im=UIGraphicsImageRenderer(size:size,format:f).image { c in fills[i].setFill();c.fill(CGRect(origin:.zero,size:size)) }
            return WorkoutPhotoDraft(jpegData:try XCTUnwrap(im.jpegData(compressionQuality:0.85)))
        }
        try await ReviewDemoPhotoStore.shared.replace(workout:workout,ownerID:ReviewDemoMode.userID,photos:drafts,expectedPhotoIDs:nil)
        let refs=try await ReviewDemoPhotoStore.shared.load(workoutID:workout.id,ownerID:ReviewDemoMode.userID)
        guard refs.count==3 else {throw Failure.readiness}
        let bytes=try refs.map {try XCTUnwrap(ReviewDemoPhotoStore.shared.bytes(for:$0))}
        let images=try bytes.map {try XCTUnwrap(UIImage(data:$0))}
        return Fixture(references:refs,images:images,evidence:[
            "sizes":sizes.map{[Int($0.width),Int($0.height)]},"colors":["red","green","blue"],"jpegQuality":0.85,
            "generatedSHA256":try drafts.map{SHA256.hash(data:try XCTUnwrap($0.jpegData)).map{String(format:"%02x",$0)}.joined()},
            "storedSHA256":bytes.map{SHA256.hash(data:$0).map{String(format:"%02x",$0)}.joined()},
            "decodedSizes":try images.map {im -> [Int] in let cg=try XCTUnwrap(im.cgImage);return [cg.width,cg.height]},
            "photoIDs":refs.map{$0.id.uuidString}])
    }
    private func mounted(_ root:UIViewController,width:CGFloat,run:(UIWindow) async throws -> Void) async throws {
        let scope=CommunitySafetyStore.shared,owner=scope.viewerID,generation=scope.accountGeneration,revision=scope.revision
        let old=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap(\.windows).first(where:{$0.isKeyWindow})
        let scene=try XCTUnwrap(old?.windowScene ?? UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first(where:{$0.activationState == .foregroundActive}))
        let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:width,height:260)
        window.rootViewController=root;window.makeKeyAndVisible();root.view.frame=window.bounds
        func cleanup(){window.isHidden=true;window.rootViewController=nil;old?.makeKey()}
        defer{cleanup()}
        do {
            try await run(window);cleanup()
            XCTAssertNil(window.rootViewController);XCTAssertTrue(old==nil || old?.isKeyWindow==true)
            XCTAssertEqual(scope.viewerID,owner);XCTAssertEqual(scope.accountGeneration,generation);XCTAssertEqual(scope.revision,revision)
            try json(["windowDetached":window.rootViewController==nil,"previousKeyWindowRestored":old==nil || old?.isKeyWindow==true,"scopeUnchanged":scope.viewerID==owner && scope.accountGeneration==generation && scope.revision==revision],name:"product clip window cleanup")
        } catch {
            cleanup();try json(["error":String(describing:error),"windowDetached":window.rootViewController==nil,"previousKeyWindowRestored":old==nil || old?.isKeyWindow==true],name:"product clip window failure cleanup");throw error
        }
    }
    private func observe(_ root:UIViewController,window:UIWindow,geometry:WorkoutMediaStripGeometry,labels:[String],name:String,fixture:[String:Any],roundedRoute:Bool?=nil) async throws -> [String:Any] {
        var observations=[[String:Any]](),final:UIImage?
        let start=ContinuousClock.now
        do {
            // Fixed 20 observations, no early-success capture or retry-on-instability.
            for _ in 0..<20 {
                try await Task.sleep(for:.milliseconds(50));window.layoutIfNeeded();root.view.layoutIfNeeded()
                let p=try XCTUnwrap(pager(root)),scroll=try XCTUnwrap(p.view.subviews.compactMap{$0 as? UIScrollView}.first)
                let children=pageHosts(p,scroll),whole=try image(root.view);final=whole
                var probes=[String:[Int]]()
                if let roundedRoute {
                    let frame=try XCTUnwrap(geometry.frames.first)
                    probes=["routeCorner2":[Int(floor(frame.minX))+2,2],"routeEdgeMid2":[Int(floor(frame.midX)),2],"routeCenter":[Int(floor(frame.midX)),130]]
                    if roundedRoute {probes["outsideInsetMid"]=[8,130]}
                }
                let state:[String:Any]=[
                    "scrollBounds":rect(scroll.bounds),"scrollLayer":layer(scroll.layer),"scrollPresentation":scroll.layer.presentation().map(layer) ?? [:],
                    "scrollPresentationViewport":presentationViewport(scroll,root:root.view) as Any? ?? NSNull(),
                    "contentOffset":[Double(scroll.contentOffset.x),Double(scroll.contentOffset.y)],"contentSize":[Double(scroll.contentSize.width),Double(scroll.contentSize.height)],
                    "pages":try children.map {c -> [String:Any] in [
                        "hostIdentity":String(describing:ObjectIdentifier(c)),"viewIdentity":String(describing:ObjectIdentifier(c.view)),
                        "parentIsPager":c.parent===p,"directScrollChild":c.view.superview===scroll,"frame":rect(c.view.frame),"bounds":rect(c.view.bounds),
                        "viewportFrame":rect(c.view.convert(c.view.bounds,to:root.view)),"clips":c.view.clipsToBounds,"layer":layer(c.view.layer),
                        "presentation":c.view.layer.presentation().map(layer) ?? [:],"presentationViewportFrame":presentationViewport(c.view,root:root.view) as Any? ?? NSNull(),
                        "isolatedHostColors":try colors(image(c.view))]},"windowColors":try colors(whole,probes:probes)]
                observations.append(state)
            }
            let tail=try observations.suffix(3).map{try JSONSerialization.data(withJSONObject:$0,options:[.sortedKeys])}
            guard tail.count==3,tail.dropFirst().allSatisfy({$0==tail[0]}) else {throw Failure.unstable}
            let last=try XCTUnwrap(observations.last),pages=try XCTUnwrap(last["pages"] as? [[String:Any]])
            guard pages.count==labels.count,geometry.frames.count==labels.count else {throw Failure.containment}
            let duration=start.duration(to:.now).components,elapsed=Double(duration.seconds)*1000+Double(duration.attoseconds)/1e15
            guard elapsed>=300 else{throw Failure.unstable}
            let offset=try XCTUnwrap(last["contentOffset"] as? [Double]),size=try XCTUnwrap(last["contentSize"] as? [Double])
            XCTAssertEqual(offset[0],0,accuracy:1);XCTAssertEqual(offset[1],0,accuracy:1)
            XCTAssertEqual(size[0],Double(geometry.contentWidth),accuracy:1);XCTAssertEqual(size[1],260,accuracy:1)
            let present=observations.suffix(3).allSatisfy {v in
                guard let sp=v["scrollPresentation"] as? [String:Any],!sp.isEmpty,v["scrollPresentationViewport"] is [Double],let ps=v["pages"] as? [[String:Any]] else{return false}
                return ps.count==labels.count && ps.allSatisfy {($0["presentation"] as? [String:Any])?.isEmpty==false && $0["presentationViewportFrame"] is [Double]}
            }
            guard present else{throw Failure.missingPresentation}
            let whole=try XCTUnwrap(last["windowColors"] as? [String:Any])
            for (i,page) in pages.enumerated() {
                guard page["clips"] as? Bool == true,page["parentIsPager"] as? Bool == true,page["directScrollChild"] as? Bool == true else {throw Failure.containment}
                let f=try XCTUnwrap(page["frame"] as? [Double]),isolated=try XCTUnwrap(page["isolatedHostColors"] as? [String:Any])
                XCTAssertEqual(f[0],Double(geometry.frames[i].minX),accuracy:1);XCTAssertEqual(f[1],0,accuracy:1)
                XCTAssertEqual(f[2],Double(geometry.frames[i].width),accuracy:1);XCTAssertEqual(f[3],260,accuracy:1)
                guard isolated["centerClass"] as? String == labels[i] else{throw Failure.readiness}
                let color=try XCTUnwrap(whole[labels[i]] as? [String:Any]),xs=try XCTUnwrap(color["centerRowXs"] as? [Int])
                let expectedLeft=max(0,Double(geometry.frames[i].minX)-offset[0]),expectedRight=min(Double(window.bounds.width),Double(geometry.frames[i].maxX)-offset[0])
                if expectedRight-expectedLeft>3 {
                    let lo=try XCTUnwrap(color["minX"] as? Int),hi=try XCTUnwrap(color["maxX"] as? Int)
                    XCTAssertGreaterThanOrEqual(lo,Int(floor(expectedLeft))-1,"No color can overflow its own host left edge")
                    XCTAssertLessThanOrEqual(hi,Int(ceil(expectedRight)),"No color can overflow its own host right edge")
                    XCTAssertEqual(Double(try XCTUnwrap(xs.first)),expectedLeft,accuracy:2)
                    XCTAssertEqual(Double(try XCTUnwrap(xs.last))+1,expectedRight,accuracy:2)
                    XCTAssertEqual(Double(xs.count),expectedRight-expectedLeft,accuracy:3,"Neighbor peek width preserved")
                } else {XCTAssertTrue(xs.isEmpty)}
            }
            if let roundedRoute {
                let probes=try XCTUnwrap(whole["probes"] as? [String:[String:Any]])
                let corner=try XCTUnwrap(probes["routeCorner2"]),edge=try XCTUnwrap(probes["routeEdgeMid2"]),center=try XCTUnwrap(probes["routeCenter"])
                XCTAssertEqual(edge["class"] as? String,"red");XCTAssertEqual(center["class"] as? String,"red")
                XCTAssertEqual(corner["class"] as? String,roundedRoute ? "other":"red")
                if roundedRoute {
                    for probe in [corner,try XCTUnwrap(probes["outsideInsetMid"])] {
                        let rgba=try XCTUnwrap(probe["rgba"] as? [Int]);XCTAssertEqual(rgba.count,4)
                        XCTAssertTrue(rgba.prefix(3).allSatisfy{$0>240},"Composed window corner/inset must expose explicit white fixture background")
                        XCTAssertEqual(rgba.last,255)
                    }
                }
            }
            let identities=pages.compactMap{$0["hostIdentity"] as? String}
            let observationsHaveDefaultClip=observations.allSatisfy {v in (v["pages"] as? [[String:Any]])?.allSatisfy{$0["clips"] as? Bool == true} == true}
            XCTAssertTrue(observationsHaveDefaultClip)
            var report:[String:Any]=["schemaVersion":1,"stage":name,"fixture":fixture,"expectedFrames":geometry.frames.map(rect),"expectedLabels":labels,
                "observations":observations,"stable":last,"finalThreeStable":true,"presentationLayersObserved":present,"elapsedMs":elapsed,
                "observationCount":20,"intervalMilliseconds":50,"defaultProductClipOnly":true,"testWritesClip":false,"allObservedHostsClipped":observationsHaveDefaultClip,"hostIdentities":identities,
                "limits":["Whole-view then isolated-page raster captures are sequential, not atomic.","Private photo-ID dictionary is not read; expected mapping uses frame order and independent decoded color.","Synthetic route color checks production media corner shape, not real map tiles/labels.","No gallery, menu, gesture, performance or physical-device claim."]]
            if roundedRoute != nil {
                report["routePixelContractVersion"]=2
                report["routeCornerObservation"]="whole stable PNG canonical pixels; isolated draw background not asserted"
            }
            attach(try XCTUnwrap(final),name:"product clip "+name+" stable")
            try json(report,name:"product clip "+name+" result");return report
        } catch {
            if let final{attach(final,name:"product clip "+name+" failure raster")}
            try json(["stage":name,"error":String(describing:error),"observations":observations],name:"product clip "+name+" failure");throw error
        }
    }
    func testDefaultClipActualPhotos393() async throws {try await actualPhotos(width:393)}
    func testDefaultClipActualPhotos402() async throws {try await actualPhotos(width:402)}
    private func actualPhotos(width:CGFloat) async throws {
        executionTimeAllowance=30;guard safeSyntheticHost() else{return}
        let f=try await fixture(),runtime=try XCTUnwrap(ReviewDemoController.shared.runtime)
        let scope=CommunitySafetyStore.shared,owner=scope.viewerID,generation=scope.accountGeneration,revision=scope.revision
        let row=WorkoutPhotoMediaRow(workoutID:nil,photos:f.references,photosAreKnown:true,hasRoute:false){Color.purple}.environmentObject(runtime.auth).frame(width:width,height:260)
        let host=UIHostingController(rootView:row);host.safeAreaRegions=[]
        try await mounted(host,width:width) { window in
            _ = try await self.observe(host,window:window,geometry:WorkoutMediaStripGeometry(widths:[260*2/3,145,width-32],viewportWidth:width),labels:["red","green","blue"],name:"photos-\(Int(width))",fixture:f.evidence)
        }
        XCTAssertEqual(scope.viewerID,owner);XCTAssertEqual(scope.accountGeneration,generation);XCTAssertEqual(scope.revision,revision)
    }
    func testDefaultClipPersistsAcrossHostReuseRootReplacementAndWidthChange() async throws {
        executionTimeAllowance=30;guard safeSyntheticHost() else{return}
        let f=try await fixture(),p=WorkoutMediaPagerController(),widths:[CGFloat]=[260*2/3,145,370]
        func pages(_ order:[Int])->[WorkoutMediaPage] {
            order.enumerated().map {i,j in WorkoutMediaPage(id:"synthetic-\(i)",content:AnyView(Image(uiImage:f.images[j]).resizable().scaledToFill().frame(maxWidth:.infinity,maxHeight:.infinity)),width:widths[i])}
        }
        p.update(pages:pages([0,1,2]),selectedID:"synthetic-0",animated:false,inset:16,spacing:8)
        try await mounted(p,width:402) { window in
            let first=try await self.observe(p,window:window,geometry:WorkoutMediaStripGeometry(widths:widths,viewportWidth:402),labels:["red","green","blue"],name:"reuse-before",fixture:f.evidence)
            let ids=try XCTUnwrap(first["hostIdentities"] as? [String])
            p.update(pages:pages([1,2,0]),selectedID:"synthetic-0",animated:false,inset:16,spacing:8)
            let replaced=try await self.observe(p,window:window,geometry:WorkoutMediaStripGeometry(widths:widths,viewportWidth:402),labels:["green","blue","red"],name:"reuse-root-replaced",fixture:f.evidence)
            XCTAssertEqual(replaced["hostIdentities"] as? [String],ids)
            window.frame.size.width=393;p.view.frame=window.bounds;p.view.setNeedsLayout()
            let resized=try await self.observe(p,window:window,geometry:WorkoutMediaStripGeometry(widths:widths,viewportWidth:393),labels:["green","blue","red"],name:"reuse-resized393",fixture:f.evidence)
            XCTAssertEqual(resized["hostIdentities"] as? [String],ids)
        }
    }
    func testSyntheticRouteCornerWithPhotoNeighbor() async throws {try await routeCorners(withPhotos:true)}
    func testSyntheticSoloRouteKeepsSquareCorners() async throws {try await routeCorners(withPhotos:false)}
    private func routeCorners(withPhotos:Bool) async throws {
        executionTimeAllowance=30;guard safeSyntheticHost() else{return}
        let f=try await fixture(),runtime=try XCTUnwrap(ReviewDemoController.shared.runtime)
        let refs=withPhotos ? Array(f.references.suffix(2)):[]
        // Fixed primary colors, not SwiftUI semantic Color.red. Record measured swatches.
        func swatch(_ color:UIColor) throws -> [String:Any] {
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let image=UIGraphicsImageRenderer(size:CGSize(width:4,height:4),format:format).image {c in color.setFill();c.fill(CGRect(x:0,y:0,width:4,height:4))}
            return try self.colors(image)
        }
        let red=try swatch(UIColor.red),white=try swatch(UIColor.white)
        XCTAssertEqual(red["corner2RGBA"] as? [Int],[255,0,0,255]);XCTAssertEqual(white["corner2RGBA"] as? [Int],[255,255,255,255])
        var routeFixture=f.evidence
        routeFixture["routeFixture"]=["color":"Color(uiColor: UIColor.red)","background":"Color(uiColor: UIColor.white)","redSwatch":red,"whiteSwatch":white]
        let row=WorkoutPhotoMediaRow(workoutID:nil,photos:refs,photosAreKnown:true,hasRoute:true){Color(uiColor: UIColor.red)}.environmentObject(runtime.auth).frame(width:393,height:260).background(Color(uiColor: UIColor.white))
        let host=UIHostingController(rootView:row);host.safeAreaRegions=[]
        let widths:[CGFloat]=withPhotos ? [260*4/3,145,361]:[393]
        try await mounted(host,width:393) {window in
            _ = try await self.observe(host,window:window,geometry:WorkoutMediaStripGeometry(widths:widths,viewportWidth:393,inset:withPhotos ? 16:0),labels:withPhotos ? ["red","green","blue"]:["red"],name:withPhotos ? "route-mixed-corner10":"route-solo-corner0",fixture:routeFixture,roundedRoute:withPhotos)
        }
    }
}

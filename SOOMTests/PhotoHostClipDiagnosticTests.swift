import XCTest
import SwiftUI
import UIKit
import CryptoKit
@testable import SOOM

@MainActor final class PhotoHostClipDiagnosticTests: XCTestCase {
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
    private enum Failure: Error { case readiness, unstable, containment, render, baselineAlreadyClipped, missingPresentation }
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
    private func colors(_ image: UIImage) throws -> [String: Any] {
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
    func testStableUnclippedControl() async throws { try await run(clipped:false) }
    func testStablePageHostClipOnly() async throws { try await run(clipped:true) }
    private func run(clipped: Bool) async throws {
        executionTimeAllowance=30
        guard safeSyntheticHost() else { return }
        let mode=clipped ? "clip":"control", demo=ReviewDemoController.shared
        let runtime=try XCTUnwrap(demo.runtime)
        let scope=CommunitySafetyStore.shared
        let owner=scope.viewerID, generation=scope.accountGeneration, revision=scope.revision
        let store=SwiftDataUnifiedWorkoutStore(modelContext:runtime.storage.container.mainContext)
        let recent=try await store.fetchRecentWorkouts(days:90)
        let workout=try XCTUnwrap(recent.first)
        let sizes=[CGSize(width:600,height:900),CGSize(width:500,height:1000),CGSize(width:1400,height:600)]
        let fills:[UIColor]=[.red,.green,.blue]
        let drafts=try sizes.enumerated().map { i,size in
            let format=UIGraphicsImageRendererFormat();format.scale=1
            let image=UIGraphicsImageRenderer(size:size,format:format).image { c in fills[i].setFill();c.fill(CGRect(origin:.zero,size:size)) }
            return WorkoutPhotoDraft(jpegData:try XCTUnwrap(image.jpegData(compressionQuality:0.85)))
        }
        try await ReviewDemoPhotoStore.shared.replace(workout:workout,ownerID:ReviewDemoMode.userID,photos:drafts,expectedPhotoIDs:nil)
        let refs=try await ReviewDemoPhotoStore.shared.load(workoutID:workout.id,ownerID:ReviewDemoMode.userID)
        XCTAssertEqual(refs.count,3)
        let storedBytes=try refs.map { try XCTUnwrap(ReviewDemoPhotoStore.shared.bytes(for:$0)) }
        let storedDimensions=try storedBytes.map { data -> [Int] in
            let cg=try XCTUnwrap(UIImage(data:data)?.cgImage);return [cg.width,cg.height]
        }
        let row=WorkoutPhotoMediaRow(workoutID:nil,photos:refs,hasRoute:false) { Color.purple }
            .environmentObject(runtime.auth).frame(width:402,height:260)
        let host=UIHostingController(rootView:row);host.safeAreaRegions=[]
        let previous=UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.flatMap(\.windows).first(where:{$0.isKeyWindow})
        let scene=try XCTUnwrap(previous?.windowScene ?? UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first(where:{$0.activationState == .foregroundActive}))
        let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:402,height:260)
        window.rootViewController=host;window.makeKeyAndVisible();host.view.frame=window.bounds
        var detached=false, restored=false
        func cleanup() { window.isHidden=true;window.rootViewController=nil;previous?.makeKey();detached=window.rootViewController==nil;restored=previous==nil || previous?.isKeyWindow==true }
        defer { cleanup() }
        let expected=WorkoutMediaStripGeometry(widths:[260*2/3,145,370],viewportWidth:402)
        var report:[String:Any]=["schemaVersion":1,"case":mode,"phaseFailure":NSNull(),"viewport":[402,260],"hasMap":false,"fixtureSizes":sizes.map{[Int($0.width),Int($0.height)]},"fixtureColors":["red","green","blue"],"fixtureSHA256":try drafts.map {SHA256.hash(data:try XCTUnwrap($0.jpegData)).map{String(format:"%02x",$0)}.joined()},"jpegQuality":0.85,"productMutation":false,"clipVariableOnly":true,"preparationSamples":20,"observationSamples":20,"sleepMilliseconds":50,"requiredFinalStableSamples":3,"minimumObservationMilliseconds":300,"pageIDMapping":"expected photo IDs by sorted host frame; private page dictionary not read","fixturePhotoIDs":refs.map{$0.id.uuidString},"notGestureOrWholeFeedProof":true,"notDeviceScreenshot":true]
        report["limits"]=["Early sample is after a 50ms wait and additional isolated-host raster measurement; not timing-equivalent to original batch12 early capture.","Model and presentation host geometry plus clip intervention do not identify a particular internal SwiftUI subtree cause.","Control normal means nonreproduction, not evidence that clipping fixed the original failure.","Fixed observation rasterization may itself affect rendering; both conditions use the same counts and waits.","Each sample renders whole host first then three isolated page hosts; geometry/raster fields are sequential observations, not an atomic instant.","Fresh processes are enforced by the external one-shot runtime, not by this XCTest class."]
        report["storedFixtureSHA256"]=storedBytes.map {SHA256.hash(data:$0).map{String(format:"%02x",$0)}.joined()}
        report["storedFixtureDecodedSizes"]=storedDimensions
        report["expectedFrames"]=expected.frames.map(rect)
        var phase="preparation", earlyImage:UIImage?, early:[String:Any]?, prepared=[[String:Any]](), observed=[[String:Any]]()
        let start=ContinuousClock.now
        func elapsed() -> Double { let d=start.duration(to:.now).components;return Double(d.seconds)*1000+Double(d.attoseconds)/1e15 }
        func sample() throws -> (UIImage,[String:Any]) {
            window.layoutIfNeeded();host.view.layoutIfNeeded()
            let p=try XCTUnwrap(pager(host)),scroll=try XCTUnwrap(p.view.subviews.compactMap{$0 as? UIScrollView}.first)
            let children=pageHosts(p,scroll)
            let whole=try image(host.view)
            let state:[String:Any]=["scrollFrame":rect(scroll.frame),"scrollBounds":rect(scroll.bounds),"scrollLayer":layer(scroll.layer),"scrollPresentation":scroll.layer.presentation().map(layer) ?? [:],"scrollPresentationViewport":presentationViewport(scroll,root:host.view) as Any? ?? NSNull(),"scrollClips":scroll.clipsToBounds,"contentOffset":[Double(scroll.contentOffset.x),Double(scroll.contentOffset.y)],"contentSize":[Double(scroll.contentSize.width),Double(scroll.contentSize.height)],"pageCount":children.count,"pages":try children.enumerated().map { i,c -> [String:Any] in
                ["index":i,"hostIdentity":String(describing:ObjectIdentifier(c)),"viewIdentity":String(describing:ObjectIdentifier(c.view)),"parentIsPager":c.parent===p,"directScrollChild":c.view.superview===scroll,"frame":rect(c.view.frame),"bounds":rect(c.view.bounds),"viewportFrame":rect(c.view.convert(c.view.bounds,to:host.view)),"presentationViewportFrame":presentationViewport(c.view,root:host.view) as Any? ?? NSNull(),"clips":c.view.clipsToBounds,"layer":layer(c.view.layer),"presentation":c.view.layer.presentation().map(layer) ?? [:],"isolatedHostColors":try colors(image(c.view))]
            },"windowColors":try colors(whole)]
            return (whole,state)
        }
        func ready(_ value:[String:Any]) -> Bool {
            guard let pages=value["pages"] as? [[String:Any]],pages.count==3,let size=value["contentSize"] as? [Double],abs(size[0]-Double(expected.contentWidth))<2 else{return false}
            let names=["red","green","blue"]
            return pages.enumerated().allSatisfy { i,p in
                guard let f=p["frame"] as? [Double],let c=p["isolatedHostColors"] as? [String:Any] else{return false}
                return abs(f[0]-Double(expected.frames[i].minX))<1 && abs(f[2]-Double(expected.frames[i].width))<1 && c["centerClass"] as? String == names[i] && p["parentIsPager"] as? Bool == true && p["directScrollChild"] as? Bool == true
            }
        }
        do {
            for i in 0..<20 {
                try await Task.sleep(for:.milliseconds(50));let (im,state)=try sample();prepared.append(state)
                if early==nil,let size=state["contentSize"] as? [Double],abs(size[0]-Double(expected.contentWidth))<2 {early=state;earlyImage=im;report["earlySampleIndex"]=i;report["earlyElapsedMs"]=elapsed()}
            }
            report["preparation"]=prepared
            guard let earlyImage,let early,let last=prepared.last,ready(last) else{throw Failure.readiness}
            report["early"]=early;report["earlyBeforeTreatment"]=true
            attach(earlyImage,name:"host clip "+mode+" early")
            let p=try XCTUnwrap(pager(host)),scroll=try XCTUnwrap(p.view.subviews.compactMap{$0 as? UIScrollView}.first),children=pageHosts(p,scroll)
            guard children.count==3,children.allSatisfy({$0.parent===p && $0.view.superview===scroll}) else{throw Failure.containment}
            report["treatmentHostIdentities"]=children.map{String(describing:ObjectIdentifier($0))}
            report["beforeTreatmentClips"]=children.map{$0.view.clipsToBounds}
            guard children.allSatisfy({ !$0.view.clipsToBounds }) else {throw Failure.baselineAlreadyClipped}
            report["clipsChangedCount"]=clipped ? children.filter{!$0.view.clipsToBounds}.count : 0
            if clipped { children.forEach{$0.view.clipsToBounds=true} }
            phase="fixed-observation";let began=elapsed();var finalImage:UIImage?
            for _ in 0..<20 {try await Task.sleep(for:.milliseconds(50));let (im,state)=try sample();observed.append(state);finalImage=im}
            report["observations"]=observed;report["observationElapsedMs"]=elapsed()-began
            let presentationsObserved=observed.suffix(3).allSatisfy { value in
                guard let scrollPresentation=value["scrollPresentation"] as? [String:Any],!scrollPresentation.isEmpty,
                      let scrollViewport=value["scrollPresentationViewport"] as? [Double],scrollViewport.count==4,
                      let pages=value["pages"] as? [[String:Any]],pages.count==3 else{return false}
                return pages.allSatisfy { page in
                    guard let presentation=page["presentation"] as? [String:Any],!presentation.isEmpty,
                          let viewport=page["presentationViewportFrame"] as? [Double],viewport.count==4 else{return false}
                    return true
                }
            }
            report["presentationLayersObserved"]=presentationsObserved
            guard presentationsObserved else{throw Failure.missingPresentation}
            let tail=try observed.suffix(3).map{try JSONSerialization.data(withJSONObject:$0,options:[.sortedKeys])}
            let stable=tail.count==3 && tail.dropFirst().allSatisfy{$0==tail[0]}
            report["finalThreeStable"]=stable
            guard stable,elapsed()-began>=300,let last=observed.last,ready(last) else{throw Failure.unstable}
            XCTAssertEqual(scroll.contentOffset.x,0,accuracy:1);XCTAssertEqual(scroll.contentSize.height,260,accuracy:1)
            XCTAssertEqual(children.map{String(describing:ObjectIdentifier($0))},pageHosts(p,scroll).map{String(describing:ObjectIdentifier($0))})
            if clipped {XCTAssertTrue(children.allSatisfy{$0.view.clipsToBounds})}
            let stablePages=try XCTUnwrap(last["pages"] as? [[String:Any]])
            let identities=children.map{String(describing:ObjectIdentifier($0))}
            let identitiesStable=observed.allSatisfy { value in
                (value["pages"] as? [[String:Any]])?.compactMap{$0["hostIdentity"] as? String} == identities
            }
            let beforeClips=try XCTUnwrap(report["beforeTreatmentClips"] as? [Bool])
            let clippingAsAssigned=stablePages.compactMap{$0["clips"] as? Bool} == (clipped ? [true,true,true]:beforeClips)
            XCTAssertTrue(identitiesStable);XCTAssertTrue(clippingAsAssigned)
            report["observationHostIdentitiesStable"]=identitiesStable
            report["clippingAsAssigned"]=clippingAsAssigned
            report["stable"]=last;report["stableElapsedMs"]=elapsed();report["decodedHostCentersVerified"]=true
            report["scopeUnchanged"]=scope.viewerID==owner && scope.accountGeneration==generation && scope.revision==revision
            XCTAssertTrue(report["scopeUnchanged"] as? Bool == true)
            attach(try XCTUnwrap(finalImage),name:"host clip "+mode+" stable")
            cleanup();report["windowDetached"]=detached;report["previousKeyWindowRestored"]=restored
            XCTAssertTrue(detached);XCTAssertTrue(restored)
            try json(report,name:"host clip "+mode+" result")
        } catch {
            report["phaseFailure"]=phase;report["error"]=String(describing:error);report["preparation"]=prepared;report["observations"]=observed
            cleanup();report["windowDetached"]=detached;report["previousKeyWindowRestored"]=restored
            try json(report,name:"host clip "+mode+" failure");throw error
        }
    }
}

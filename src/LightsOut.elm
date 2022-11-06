module LightsOut exposing (..)

import Browser
import Time
import Angle
import Camera3d
import Color
import Direction3d
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events as Evts
import Length
import Pixels
import Point3d
import Quantity
import Cylinder3d
import Triangle3d
import Scene3d
import Axis3d
import Scene3d.Material as Material
import Viewpoint3d
import Dict exposing (Dict)
import Html.Events.Extra.Pointer as Pointer
import Html.Events.Extra.Mouse as Mouse
import Random


main = Browser.element { init = init
                       , update = update
                       , view = view
                       , subscriptions = subscriptions
                       }

type alias Model = { level : Int
                   , vertices : List (Point3d.Point3d Length.Meters WorldCoordinates)
                   , edges : List Edge
                   , faces : List Face
                   , faceAdjList : List (List Int)
                   , on :List (Bool)
                   , theta : Float
                   , start : Maybe {x:Float, y:Float}
                   }
type alias Vertex = {x:Float, y:Float, z:Float}
type alias Edge = {from: Int, to:Int}
type alias Face = List Int

type Msg = Elapsed Time.Posix
    | Divide
    | RStart {x: Float, y: Float}
    | RMove {x: Float, y: Float}
    | REnd {x: Float, y: Float} Int
    | RDbl Int
    | Random
    | Toggle (List Int)

type WorldCoordinates = WorldCoordinates

initialVertices = [ (Point3d.meters 0 0 1 )
                  , (Point3d.meters 1 0 0 )
                  , (Point3d.meters 0 1 0 )
                  , (Point3d.meters -1 0 0)
                  , (Point3d.meters 0 -1 0)
                  , (Point3d.meters 0 0 -1)
                  ]

initialEdges = [ Edge 0 1
               , Edge 0 2
               , Edge 0 3
               , Edge 0 4
               , Edge 5 1
               , Edge 5 2
               , Edge 5 3
               , Edge 5 4
               , Edge 1 2
               , Edge 2 3
               , Edge 3 4
               , Edge 4 1
               ]

initialFaces = [ [0, 1, 2]
               , [0, 2, 3]
               , [0, 3, 4]
               , [0, 4, 1]
               , [5, 1, 2]
               , [5, 2, 3]
               , [5, 3, 4]
               , [5, 4, 1]
               ]

init : () -> (Model, Cmd Msg)
init _ = ( Model 0
               initialVertices
               initialEdges
               initialFaces
               (Debug.log "initadj" <| adjList initialFaces)
               (List.repeat (List.length initialFaces) True)
               0
               Nothing
         , Cmd.none)

update : Msg -> Model -> (Model, Cmd Msg)
update  msg model =
    case msg of
        Elapsed t ->
            --({model| vertices = List.map rotation model.vertices}
            (model
            , Cmd.none)
        Divide ->
            ( refine model, Cmd.none)
        RStart pos ->
            let
                dummy = Debug.log "RStart" pos
            in
            ({model | start = Just pos}, Cmd.none)
        RMove pos ->
            let
                --dummy = Debug.log "Rmove" pos
                dir = Debug.log "" <| case model.start of
                                          Just from -> { x = -pos.y + from.y
                                                       , y = pos.x - from.x
                                                       }
                                          Nothing -> {x=1,y=0}
                axis = Maybe.withDefault Axis3d.x <|
                       Axis3d.throughPoints
                           Point3d.origin
                           (Point3d.meters  dir.x 0 dir.y )
                angle = Angle.degrees  (0.5*(sqrt (dir.x^2 + dir.y^2)))
                vertices = List.map (\v -> Point3d.rotateAround
                                           axis angle v
                                    ) model.vertices
            in
            ({model | start = case model.start of
                                  Just drom -> Just pos
                                  Nothing -> Nothing
             ,vertices = case model.start of
                             Just from ->  vertices
                             Nothing -> model.vertices
             }
            , Cmd.none)
        REnd pos idx ->
            let
                dummy = Debug.log "REnd" pos
                newModel = case model.start of
                               Just start ->
                                   if pos == start then
                                       switch idx model
                                   else
                                       {model | start = Nothing}
                               Nothing ->
                                   model
            in
                (newModel, Cmd.none)
        RDbl idx ->
            let
                dummy = Debug.log "RDbl" idx
            in
                (switch idx model, Cmd.none)
        Random ->
            let
                gen = Random.list (2*(List.length model.faces)) (Random.int 0 ((List.length model.faces)-1))
            in
                (model, Random.generate Toggle gen)
        Toggle indices ->
            (toggle indices model, Cmd.none)

toggle : List Int -> Model -> Model
toggle indices model =
    List.foldl (\i m -> switch i m) model indices

                
switch : Int -> Model -> Model
switch i model =
    let
        range = List.append [i] <| List.concat <| List.take 1 <| List.drop i model.faceAdjList
        onOff = List.indexedMap (\idx on -> if List.member idx range then
                                                not on
                                            else
                                                on
                                ) model.on
    in
        {model | on = onOff, start=Nothing}

faceCenter: List Int -> List (Point3d.Point3d Length.Meters WorldCoordinates) -> Point3d.Point3d Length.Meters WorldCoordinates
faceCenter face vertices =
    let
        getVertex : Int -> Point3d.Point3d Length.Meters WorldCoordinates
        getVertex i =
            Maybe.withDefault (Point3d.meters 0 0 0) <|
                List.head <| List.drop i vertices
        p = Maybe.withDefault 0 <| List.head face
        q = Maybe.withDefault 0 <| List.head <| List.drop 1 face
        r = Maybe.withDefault 0 <| List.head <| List.drop 2 face
    in
        Maybe.withDefault Point3d.origin <|
            Point3d.circumcenter (getVertex p)
                (getVertex q)
                (getVertex r)
    
adjacent : Face -> Face -> Bool
adjacent f1 f2 =
    let
        intersection = List.foldl (\v num -> if List.member v f1 then
                                                 num+1
                                             else
                                                 num
                                  ) 0 f2
    in
        if intersection == 2 then
            True
        else
            False

adjList : List Face -> List (List Int)
adjList faces =
    List.map (\f1 ->
                  List.concat <|
                  List.indexedMap (\i f2 -> if adjacent f1 f2 then
                                                [i]
                                            else
                                                []
                                  ) faces
             ) faces
                    
refine : Model -> Model
refine model =
    let
        edges = model.edges
        vertices = model.vertices
        faces = model.faces

        getVertex : Int -> Point3d.Point3d Length.Meters WorldCoordinates
        getVertex i =
            Maybe.withDefault (Point3d.meters 0 0 0) <|
                List.head <| List.drop i vertices
        midPoint  v w =
            let
                m = Point3d.midpoint v w
                p = Point3d.toRecord Length.inMeters m
                r = 1/(sqrt (p.x^2+p.y^2+p.z^2))
            in
                Point3d.scaleAbout Point3d.origin r m
        newVertices : List (Point3d.Point3d Length.Meters WorldCoordinates)
        newVertices =
            List.map (\e ->
                          let
                              v = getVertex e.from
                              w = getVertex e.to
                          in
                              midPoint v w
                     ) edges
        midPoints : Dict (Int, Int) Int
        midPoints =
            List.foldl (\e dict ->
                            let
                                v = getVertex e.from
                                w = getVertex e.to
                            in
                                Dict.insert (e.from, e.to)
                                    ((Dict.size dict)+(List.length vertices))
                                    dict
                       )
                Dict.empty
                edges
        divideEdge : Edge -> List Edge
        divideEdge edge =
            [{ from = edge.from
             , to = Maybe.withDefault -1 <|
                    Dict.get (edge.from, edge.to) midPoints
             }
            ,{ from = Maybe.withDefault -1 <|
                      Dict.get (edge.from, edge.to) midPoints
             , to = edge.to
             }
            ]
        edgeFromFace : Face -> List Edge
        edgeFromFace face =
            let
                v1 = Maybe.withDefault (-1) <|  List.head face
                v2 = Maybe.withDefault (-1) <|  List.head (List.drop 1 face)
                v3 = Maybe.withDefault (-1) <|  List.head (List.drop 2 face)
                w1 = if Dict.member (v1,v2) midPoints then
                         Dict.get (v1,v2) midPoints
                     else (if Dict.member (v2,v1) midPoints then
                               Dict.get (v2,v1) midPoints
                           else
                               Nothing
                          )
                w2 = if Dict.member (v2,v3) midPoints then
                         Dict.get (v2,v3) midPoints
                     else (if Dict.member (v3,v2) midPoints then
                               Dict.get (v3,v2) midPoints
                           else
                               Nothing
                          )
                w3 = if Dict.member (v3,v1) midPoints then
                         Dict.get (v3,v1) midPoints
                     else (if Dict.member (v1,v3) midPoints then
                               Dict.get (v1,v3) midPoints
                           else
                               Nothing
                          )
            in
                case (w1,w2,w3) of
                    (Just a, Just b, Just c) ->
                        [ {from = a, to = b}
                        , {from = b, to = c}
                        , {from = c, to = a}
                        ]
                    _ ->
                        []

        newEdges : List Edge
        newEdges =
            List.concat <|
                (List.map divideEdge edges)++
                    (List.map edgeFromFace faces)

        facesFromFace : Face -> List Face
        facesFromFace face =
            let
                v1 = Maybe.withDefault (-1) <|  List.head face
                v2 = Maybe.withDefault (-1) <|  List.head (List.drop 1 face)
                v3 = Maybe.withDefault (-1) <|  List.head (List.drop 2 face)
                w1 = if Dict.member (v1,v2) midPoints then
                         Dict.get (v1,v2) midPoints
                     else (if Dict.member (v2,v1) midPoints then
                               Dict.get (v2,v1) midPoints
                           else
                               Nothing
                          )
                w2 = if Dict.member (v2,v3) midPoints then
                         Dict.get (v2,v3) midPoints
                     else (if Dict.member (v3,v2) midPoints then
                               Dict.get (v3,v2) midPoints
                           else
                               Nothing
                          )
                w3 = if Dict.member (v3,v1) midPoints then
                         Dict.get (v3,v1) midPoints
                     else (if Dict.member (v1,v3) midPoints then
                               Dict.get (v1,v3) midPoints
                           else
                               Nothing
                          )
            in
                case (w1,w2,w3) of
                    (Just a, Just b, Just c) ->
                        [ [v1, a, c]
                        , [v2, b, a]
                        , [v3, c, b]
                        , [a,b,c]
                        ]
                    _ ->
                        []
        newFaces = List.concat <| List.map facesFromFace faces
    in
        Model (model.level+1)
            (vertices++newVertices) (edges++newEdges) (faces++newFaces)
            (adjList (faces++newFaces))
            (List.repeat (List.length (faces++newFaces)) True)
            model.theta
            Nothing




rotation : Point3d.Point3d Length.Meters WorldCoordinates -> Point3d.Point3d Length.Meters WorldCoordinates
rotation v =
    Point3d.rotateAround Axis3d.z (Angle.degrees 1) v


relativePosition ev =
    {x= Tuple.first ev.pointer.offsetPos
    ,y= Tuple.second ev.pointer.offsetPos
    }

dblPosition ev =
    {x= Tuple.first ev.clientPos
    ,y= Tuple.second ev.clientPos
    }
    
view : Model -> Html Msg
view model =
    let
        material =
            Material.nonmetal
                { baseColor = Color.lightYellow
                , roughness = 0.4 -- varies from 0 (mirror-like) to 1 (matte)
                }
        onMaterial =
            Material.nonmetal
                { baseColor = Color.lightYellow
                , roughness = 0.4 -- varies from 0 (mirror-like) to 1 (matte)
                }
        offMaterial =
            Material.nonmetal
                { baseColor = Color.darkGray
                , roughness = 0.4 -- varies from 0 (mirror-like) to 1 (matte)
                }
        redMaterial =
            Material.nonmetal
                { baseColor = Color.red
                , roughness = 0.4 -- varies from 0 (mirror-like) to 1 (matte)
                }
        blackMaterial =
            Material.nonmetal
                { baseColor = Color.black
                , roughness = 0.4 -- varies from 0 (mirror-like) to 1 (matte)
                }

        verticesView = model.vertices

        point p =
            Point3d.meters p.x p.y p.z

        dist p q =
            sqrt ((p.x - q.x)^2 + (p.y - q.y)^2 + (p.z - q.z)^2 )

        vertex i =
            Maybe.withDefault (Point3d.origin) <|
                List.head <| List.drop (i) model.vertices

        xcoord f =
            -(Length.inMeters <| Point3d.yCoordinate  <| faceCenter f model.vertices)
        frontFace =
            List.concat <| List.take 1 <| List.sortBy xcoord model.faces
                    
        edge edata =
            let
                mat = if (List.member edata.from  frontFace) && (List.member edata.to frontFace) then
                          redMaterial
                      else
                          blackMaterial
                rad = if (List.member edata.from  frontFace) && (List.member edata.to frontFace) then
                          0.01
                      else
                          0.003
            in
            Scene3d.cylinderWithShadow mat <|
                Cylinder3d.startingAt
                    (vertex edata.from)
                    (Maybe.withDefault Direction3d.x <|
                         (Direction3d.from  (vertex edata.from)  (vertex edata.to)))
                    {radius = Length.meters rad
                    ,length = Point3d.distanceFrom (vertex edata.from) (vertex edata.to)
                    }
        edges = (List.map edge model.edges)

        faceView  fdata onOff=
            let
                a = Maybe.withDefault (-1) <| List.head fdata
                b = Maybe.withDefault (-1) <| List.head <| List.drop 1 fdata
                c = Maybe.withDefault (-1) <| List.head <| List.drop 2 fdata
                mat = if onOff then
                          onMaterial
                      else
                          offMaterial
            in
                Scene3d.facet mat <|
                    Triangle3d.fromVertices
                        ( (vertex a)
                        , (vertex b)
                        , (vertex c)
                        )
        faceViewFront  fdata =
            let
                a = Maybe.withDefault (-1) <| List.head fdata
                b = Maybe.withDefault (-1) <| List.head <| List.drop 1 fdata
                c = Maybe.withDefault (-1) <| List.head <| List.drop 2 fdata
            in
                Scene3d.facet redMaterial <|
                    Triangle3d.fromVertices
                        ( (vertex a)
                        , (vertex b)
                        , (vertex c)
                        )
        
        facesView =
            List.map2 faceView model.faces model.on

        getFace : Int -> Face
        getFace i =
            Maybe.withDefault ([0, 0, 0]) <|
                List.head <| List.drop i model.faces
                
        frontIdx =
            List.foldl (\i maxid -> if xcoord (getFace i) < xcoord (getFace maxid) then
                                      i
                                  else
                                      maxid
                       ) 0 (List.range 0 (List.length model.faces))

        camera =
            Camera3d.perspective
                { viewpoint =
                    Viewpoint3d.lookAt
                        { focalPoint = Point3d.origin
                        , eyePoint = Point3d.meters 0 7 0
                        , upDirection = Direction3d.positiveZ
                        }
                , verticalFieldOfView = Angle.degrees 20
                }
        myOnDbl : (Pointer.Event -> msg) -> Html.Attribute msg
        myOnDbl =
            { stopPropagation = False, preventDefault = True }
                |> Pointer.onWithOptions "dblclick"


    in
    Html.div[Pointer.onDown (\ev-> RStart (relativePosition ev))
            ,Pointer.onUp (\ev-> REnd (relativePosition ev) frontIdx)
            ,Pointer.onMove (\ev-> RMove (relativePosition ev))
            ,Mouse.onDoubleClick (\ev -> RDbl frontIdx)
            ,Attrs.style "touch-action" "none"
            ]
        [ Html.div [Attrs.style "touch-action" "none"]
              [
               Html.button [Evts.onClick Divide
                           ,Attrs.style "font-size" "30px"][
                    Html.text "divide"
                    ]
              ,Html.button [Evts.onClick Random
                           ,Attrs.style "font-size" "30px"][
                    Html.text "shuffle"
                    ]
              ]
        , Scene3d.sunny
             { camera = camera
             , clipDepth = Length.meters 0.05
             , dimensions = ( Pixels.int 600, Pixels.int 600 )
             , background = Scene3d.transparentBackground
             --, entities = spheres ++ edges ++ facesView
             , entities = edges ++ facesView
             , shadows = True
             , upDirection = Direction3d.z
             , sunlightDirection = Direction3d.xy (Angle.degrees -90)
             }
        ]


subscriptions : Model -> Sub Msg
subscriptions  model =
    Time.every 50 Elapsed

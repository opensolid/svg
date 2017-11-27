module OpenSolid.Svg.Drag
    exposing
        ( Drag
        , Event
        , Model
        , State
        , apply
        , customHandle
        , directionTipHandle
        , endPoint
        , isDragging
        , isHovering
        , lineSegmentHandle
        , none
        , pointHandle
        , process
        , rotationAround
        , startPoint
        , subscriptions
        , target
        , translation
        , triangleHandle
        , vectorTipHandle
        )

import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Mouse
import OpenSolid.BoundingBox2d as BoundingBox2d exposing (BoundingBox2d)
import OpenSolid.Direction2d as Direction2d exposing (Direction2d)
import OpenSolid.LineSegment2d as LineSegment2d exposing (LineSegment2d)
import OpenSolid.Point2d as Point2d exposing (Point2d)
import OpenSolid.Svg as Svg
import OpenSolid.Svg.Internal as Internal
import OpenSolid.Triangle2d as Triangle2d exposing (Triangle2d)
import OpenSolid.Vector2d as Vector2d exposing (Vector2d)
import Svg exposing (Svg)
import Svg.Attributes
import Svg.Events


type State t
    = Resting
    | Hovering t
    | Dragging
        { target : t
        , hoverTarget : Maybe t
        , lastPoint : Point2d
        , x0 : Float
        , y0 : Float
        }


type Event t
    = Entered t
    | Left t
    | StartedDrag { target : t, startPoint : Point2d, x0 : Float, y0 : Float }
    | DraggedTo Point2d
    | EndedDrag


type Drag t
    = Drag
        { target : t
        , startPoint : Point2d
        , endPoint : Point2d
        }


none : State t
none =
    Resting


target : Drag t -> t
target (Drag { target }) =
    target


startPoint : Drag t -> Point2d
startPoint (Drag { startPoint }) =
    startPoint


endPoint : Drag t -> Point2d
endPoint (Drag { endPoint }) =
    endPoint


translation : Drag t -> Vector2d
translation (Drag { startPoint, endPoint }) =
    Vector2d.from startPoint endPoint


rotationAround : Point2d -> Drag t -> Float
rotationAround point (Drag { startPoint, endPoint }) =
    let
        startDirection =
            Direction2d.from point startPoint

        endDirection =
            Direction2d.from point endPoint
    in
    Maybe.map2 Direction2d.angleFrom
        startDirection
        endDirection
        |> Maybe.withDefault 0


process : Event t -> State t -> ( State t, Maybe (Drag t) )
process event state =
    let
        unexpected () =
            let
                _ =
                    Debug.log "Unexpected state/event combination"
                        ( state, event )

                _ =
                    Debug.log "Please raise an issue at"
                        "https://github.com/opensolid/svg/issues/new"
            in
            ( Resting, Nothing )
    in
    case ( state, event ) of
        ( Resting, Entered target ) ->
            ( Hovering target, Nothing )

        ( Hovering hoverTarget, StartedDrag { target, startPoint, x0, y0 } ) ->
            if hoverTarget == target then
                ( Dragging
                    { target = target
                    , hoverTarget = Just target
                    , lastPoint = startPoint
                    , x0 = x0
                    , y0 = y0
                    }
                , Nothing
                )
            else
                unexpected ()

        ( Hovering hoverTarget, Left previousTarget ) ->
            if previousTarget == hoverTarget then
                ( Resting, Nothing )
            else
                unexpected ()

        ( Dragging properties, Entered hoverTarget ) ->
            if properties.hoverTarget == Nothing then
                ( Dragging { properties | hoverTarget = Just hoverTarget }, Nothing )
            else
                unexpected ()

        ( Dragging properties, Left hoverTarget ) ->
            if properties.hoverTarget == Just hoverTarget then
                ( Dragging { properties | hoverTarget = Nothing }, Nothing )
            else
                unexpected ()

        ( Dragging properties, EndedDrag ) ->
            case properties.hoverTarget of
                Nothing ->
                    ( Resting, Nothing )

                Just hoverTarget ->
                    ( Hovering hoverTarget, Nothing )

        ( Dragging { target, hoverTarget, lastPoint, x0, y0 }, DraggedTo endPoint ) ->
            ( Dragging
                { target = target
                , hoverTarget = hoverTarget
                , lastPoint = endPoint
                , x0 = x0
                , y0 = y0
                }
            , Just <|
                Drag
                    { target = target
                    , startPoint = lastPoint
                    , endPoint = endPoint
                    }
            )

        _ ->
            unexpected ()


type alias Model m t =
    { m | dragState : State t }


apply : (Drag t -> Model m t -> Model m t) -> Event t -> Model m t -> ( Model m t, Cmd msg )
apply performDrag event model =
    let
        ( updatedState, drag ) =
            process event model.dragState

        updatedModel =
            { model | dragState = updatedState }
    in
    case drag of
        Nothing ->
            ( updatedModel, Cmd.none )

        Just drag ->
            ( performDrag drag updatedModel, Cmd.none )


subscriptions : State t -> Sub (Event t)
subscriptions state =
    case state of
        Dragging { x0, y0 } ->
            let
                toEvent { x, y } =
                    DraggedTo <|
                        Point2d.fromCoordinates
                            ( x0 + toFloat x
                            , y0 - toFloat y
                            )
            in
            Sub.batch
                [ Mouse.moves toEvent
                , Mouse.ups (always EndedDrag)
                ]

        _ ->
            Sub.none


type alias Coordinates =
    { clientX : Float
    , clientY : Float
    , pageX : Float
    , pageY : Float
    }


decodeCoordinates : Decoder Coordinates
decodeCoordinates =
    Decode.map4 Coordinates
        (Decode.field "clientX" Decode.float)
        (Decode.field "clientY" Decode.float)
        (Decode.field "pageX" Decode.float)
        (Decode.field "pageY" Decode.float)


customHandle : Svg Never -> { target : t, renderBounds : BoundingBox2d } -> Svg (Event t)
customHandle shape { target, renderBounds } =
    let
        attributes =
            [ Html.Events.onWithOptions
                "mousedown"
                { stopPropagation = True
                , preventDefault = True
                }
                (decodeCoordinates
                    |> Decode.map
                        (\{ clientX, clientY, pageX, pageY } ->
                            let
                                x =
                                    BoundingBox2d.minX renderBounds + clientX

                                y =
                                    BoundingBox2d.maxY renderBounds - clientY

                                startPoint =
                                    Point2d.fromCoordinates ( x, y )
                            in
                            StartedDrag
                                { target = target
                                , startPoint = startPoint
                                , x0 = x - pageX
                                , y0 = y + pageY
                                }
                        )
                )
            , Svg.Events.onMouseOver (Entered target)
            , Svg.Events.onMouseOut (Left target)
            ]
    in
    Svg.g attributes [ shape |> Svg.map never ]


transparentFill : Svg.Attribute msg
transparentFill =
    Svg.Attributes.fill "transparent"


noStroke : Svg.Attribute msg
noStroke =
    Svg.Attributes.stroke "none"


pointHandle : Point2d -> { target : t, radius : Float, renderBounds : BoundingBox2d } -> Svg (Event t)
pointHandle point { target, radius, renderBounds } =
    let
        shape =
            Svg.point2d
                { radius = radius
                , attributes = [ noStroke, transparentFill ]
                }
                point
    in
    customHandle shape { target = target, renderBounds = renderBounds }


thickened : Float -> List (Svg.Attribute msg)
thickened padding =
    [ Svg.Attributes.fill "transparent"
    , Svg.Attributes.stroke "transparent"
    , Svg.Attributes.strokeWidth (toString (2 * padding))
    , Svg.Attributes.strokeLinejoin "round"
    , Svg.Attributes.strokeLinecap "round"
    ]


lineSegmentHandle : LineSegment2d -> { target : t, padding : Float, renderBounds : BoundingBox2d } -> Svg (Event t)
lineSegmentHandle lineSegment { target, padding, renderBounds } =
    let
        shape =
            Svg.lineSegment2d (thickened padding) lineSegment
    in
    customHandle shape { target = target, renderBounds = renderBounds }


triangleHandle : Triangle2d -> { target : t, padding : Float, renderBounds : BoundingBox2d } -> Svg (Event t)
triangleHandle triangle { target, padding, renderBounds } =
    let
        shape =
            Svg.triangle2d (thickened padding) triangle
    in
    customHandle shape { target = target, renderBounds = renderBounds }


vectorTipHandle : Point2d -> Vector2d -> { target : t, tipLength : Float, tipWidth : Float, padding : Float, renderBounds : BoundingBox2d } -> Svg (Event t)
vectorTipHandle basePoint vector { target, tipLength, tipWidth, padding, renderBounds } =
    case Vector2d.lengthAndDirection vector of
        Just ( length, direction ) ->
            let
                shape =
                    Svg.triangle2d (thickened padding) <|
                        Internal.tip
                            { tipLength = tipLength, tipWidth = tipWidth }
                            basePoint
                            length
                            direction
            in
            customHandle shape { target = target, renderBounds = renderBounds }

        Nothing ->
            pointHandle basePoint
                { target = target
                , radius = padding
                , renderBounds = renderBounds
                }


directionTipHandle : Point2d -> Direction2d -> { length : Float, tipLength : Float, tipWidth : Float, target : t, padding : Float, renderBounds : BoundingBox2d } -> Svg (Event t)
directionTipHandle basePoint direction { length, tipLength, tipWidth, padding, target, renderBounds } =
    let
        vector =
            Vector2d.with { length = length, direction = direction }
    in
    vectorTipHandle basePoint vector <|
        { target = target
        , tipLength = tipLength
        , tipWidth = tipWidth
        , padding = padding
        , renderBounds = renderBounds
        }


isHovering : t -> State t -> Bool
isHovering target state =
    case state of
        Resting ->
            False

        Hovering hoverTarget ->
            target == hoverTarget

        Dragging _ ->
            False


isDragging : t -> State t -> Bool
isDragging target state =
    case state of
        Resting ->
            False

        Hovering _ ->
            False

        Dragging properties ->
            target == properties.target

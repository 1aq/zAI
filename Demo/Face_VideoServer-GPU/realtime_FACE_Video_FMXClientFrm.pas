unit realtime_FACE_Video_FMXClientFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo, FMX.Layouts, FMX.ExtCtrls,

  System.IOUtils,

  CoreClasses, DoStatusIO,
  zDrawEngineInterface_SlowFMX, zDrawEngine, MemoryRaster, MemoryStream64,
  PascalStrings, UnicodeMixedLib, Geometry2DUnit, Geometry3DUnit, Cadencer, FFMPEG, FFMPEG_Reader,
  CommunicationFramework, CommunicationFrameworkDoubleTunnelIO_NoAuth, PhysicsIO,
  zAI_RealTime_FACE_VideoClient;

type
  Trealtime_Face_Video_FMXClientForm = class(TForm, ICadencerProgressInterface)
    SysProgress_Timer: TTimer;
    Video_RealSendTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
    procedure SysProgress_TimerTimer(Sender: TObject);
    procedure Video_RealSendTimerTimer(Sender: TObject);
  private
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
    procedure CadencerProgress(const deltaTime, newTime: Double);
    procedure OD_Result(Sender: TRealTime_FACE_VideoClient; video_stream: TMemoryStream64; video_info: TFACE_Video_Info);
  public
    drawIntf: TDrawEngineInterface_FMX;
    // ffmpeg����Ƶ��������棬Demoֻ֧���ļ��������ʹ���������ʵ��
    mpeg_r: TFFMPEG_Reader;
    // �������������ĵ�ǰ��
    mpeg_frame: TDETexture;
    cadencer_eng: TCadencer;
    realtime_od_cli: TRealTime_FACE_VideoClient;
    procedure CheckConnect;
  end;

var
  realtime_Face_Video_FMXClientForm: Trealtime_Face_Video_FMXClientForm;

implementation

{$R *.fmx}


procedure Trealtime_Face_Video_FMXClientForm.CadencerProgress(const deltaTime, newTime: Double);
begin
  EnginePool.Progress(deltaTime);
  Invalidate;
end;

procedure Trealtime_Face_Video_FMXClientForm.CheckConnect;
begin
  realtime_od_cli.AsyncConnectP('127.0.0.1', 7856, 7857, procedure(const cState: Boolean)
    begin
      if not cState then
        begin
          CheckConnect;
          exit;
        end;
      realtime_od_cli.TunnelLinkP(procedure(const lState: Boolean)
        begin
        end);
    end);
end;

procedure Trealtime_Face_Video_FMXClientForm.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  DrawPool(Self).PostScrollText(5, AText, 16, DEColor(1, 1, 1, 1));
end;

procedure Trealtime_Face_Video_FMXClientForm.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ʹ��zDrawEngine���ⲿ��ͼʱ(������Ϸ������paintbox)������Ҫһ����ͼ�ӿ�
  // TDrawEngineInterface_FMX������FMX�Ļ�ͼcore�ӿ�
  // �����ָ����ͼ�ӿڣ�zDrawEngine��Ĭ��ʹ�������դ��ͼ(�Ƚ���)
  drawIntf := TDrawEngineInterface_FMX.Create;

  // ʹ��z_ai_model.exe�༭����Game of Thrones.AI_Set��������ѵ��
  // ���������ο�zAI-Face����ָ��

  // ��demo������ʶ�������gpu��������ɣ�ǰ��֧��android��ios���κ�IOT�豸

  // mp4��Ƶ
  // ��ȡ��Ȩ������Ϸ��Ӱ
  mpeg_r := TFFMPEG_Reader.Create(umlCombineFileName(TPath.GetLibraryPath, 'GameOfThrones.mp4'));

  // ��ǰ���Ƶ���Ƶ֡
  mpeg_frame := TDrawEngine.NewTexture;

  // cadencer����
  cadencer_eng := TCadencer.Create;
  cadencer_eng.ProgressInterface := Self;

  realtime_od_cli := TRealTime_FACE_VideoClient.Create(TPhysicsClient.Create, TPhysicsClient.Create);
  realtime_od_cli.On_MMOD_Result := OD_Result;
  CheckConnect;
end;

procedure Trealtime_Face_Video_FMXClientForm.FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
var
  d: TDrawEngine;
begin
  drawIntf.SetSurface(Canvas, Sender);
  d := DrawPool(Sender, drawIntf);
  d.ViewOptions := [voFPS];
  d.FPSFontColor := DEColor(0.5, 0.5, 1, 1);

  d.FillBox(d.ScreenRect, DEColor(0, 0, 0, 1));
  d.FitDrawPicture(mpeg_frame, mpeg_frame.BoundsRectV2, d.ScreenRect, 1.0);

  // ִ�л�ͼָ��
  d.Flush;
end;

procedure Trealtime_Face_Video_FMXClientForm.OD_Result(Sender: TRealTime_FACE_VideoClient; video_stream: TMemoryStream64; video_info: TFACE_Video_Info);
begin
  video_stream.Position := 0;
  mpeg_frame.LoadFromStream(video_stream);
  mpeg_frame.Update;
  cadencer_eng.Progress;
end;

procedure Trealtime_Face_Video_FMXClientForm.SysProgress_TimerTimer(Sender: TObject);
begin
  realtime_od_cli.Progress;
end;

procedure Trealtime_Face_Video_FMXClientForm.Video_RealSendTimerTimer(Sender: TObject);
var
  mr: TMemoryRaster;
begin
  if not realtime_od_cli.LinkOk then
      exit;

  mr := NewRaster();
  while not mpeg_r.ReadFrame(mr, False) do
      mpeg_r.Seek(0);
  realtime_od_cli.Input_FACE(mr);
  disposeObject(mr);
end;

end.

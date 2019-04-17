unit VideoTrackerFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo, FMX.Layouts, FMX.ExtCtrls,

  System.IOUtils,

  CoreClasses, zAI, zAI_Common, zDrawEngineInterface_SlowFMX, zDrawEngine, MemoryRaster, MemoryStream64,
  DoStatusIO, PascalStrings, UnicodeMixedLib, Geometry2DUnit, Geometry3DUnit, Cadencer, FFMPEG, FFMPEG_Reader;

type
  TForm1 = class(TForm, ICadencerProgressInterface)
    Memo1: TMemo;
    PaintBox1: TPaintBox;
    Timer1: TTimer;
    Tracker_CheckBox: TCheckBox;
    TrackBar1: TTrackBar;
    ProgressBar1: TProgressBar;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBox1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBox1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure Timer1Timer(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
    procedure TrackBar1Change(Sender: TObject);
  private
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
    procedure CadencerProgress(const deltaTime, newTime: Double);
  public
    drawIntf: TDrawEngineInterface_FMX;
    ai: TAI;
    tracker_hnd: TTracker_Handle;
    cadencer_eng: TCadencer;
    imgList: TMemoryRasterList;
    VideoSeri: TRasterSerialized;
    tmpFileName: U_String;
    tmpFileStream: TFileStream;
    FillVideo: Boolean;
    Frame: TDETexture;

    mouse_down: Boolean;
    down_PT: TVec2;
    move_PT: TVec2;
    LastDrawRect: TRectV2;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}


procedure TForm1.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
  Memo1.GoToTextEnd;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ��ȡzAI������
  ReadAIConfig;

  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();

  // ʹ��zDrawEngine���ⲿ��ͼʱ(������Ϸ������paintbox)������Ҫһ����ͼ�ӿ�
  // TDrawEngineInterface_FMX������FMX�Ļ�ͼcore�ӿ�
  // �����ָ����ͼ�ӿڣ�zDrawEngine��Ĭ��ʹ�������դ��ͼ(�Ƚ���)
  drawIntf := TDrawEngineInterface_FMX.Create;

  // ai����
  ai := TAI.OpenEngine();
  // ��ʼ��׷����
  tracker_hnd := nil;

  // cadencer����
  cadencer_eng := TCadencer.Create;
  cadencer_eng.ProgressInterface := Self;

  // ������Ƶ��������
  imgList := TMemoryRasterList.Create;

  // ��demo�Ƕ���Ƶ���������룬չ���Ժ���10G�ռ�
  tmpFileName := ai.MakeSerializedFileName;
  tmpFileStream := TFileStream.Create(tmpFileName, fmCreate);
  VideoSeri := TRasterSerialized.Create(tmpFileStream);

  FillVideo := True;

  Frame := TDrawEngine.NewTexture();

  mouse_down := False;
  down_PT := Vec2(0, 0);
  move_PT := Vec2(0, 0);

  ProgressBar1.Visible := True;
  ProgressBar1.Min := 0;

  // ʹ��TComputeThread��̨����
  TComputeThread.RunP(nil, nil, procedure(ThSender: TComputeThread)
    var
      // mp4��Ƶ֡��ʽ
      M4: TFFMPEG_Reader;
      mr: TMemoryRaster;
      nr: TMemoryRaster;
    begin
      DoStatus('���һ�ᣬ���ڳ�ʼ����Ƶ����');
      M4 := TFFMPEG_Reader.Create(umlCombineFileName(TPath.GetLibraryPath, 'lady.mp4'));
      TThread.Synchronize(ThSender, procedure
        begin
          ProgressBar1.Max := M4.Total_Frame;
        end);

      mr := NewRaster();
      while M4.ReadFrame(mr, False) do
        begin
          if (Frame.Width <> mr.Width) or (Frame.Height <> mr.Height) then
              TThread.Synchronize(ThSender, procedure
              begin
                Frame.Assign(mr);
                Frame.ReleaseFMXResource;
              end);

          nr := NewRaster();
          nr.Assign(mr);
          // ʹ�ù�դ���л��洢�������������ݷŵ��ڴ潻��
          nr.SerializedAndRecycleMemory(VideoSeri);
          // �����ͷ�nrʹ�õĹ�դ�ڴ�ռ�
          nr.RecycleMemory;
          imgList.Add(nr);

          TThread.Synchronize(ThSender, procedure
            begin
              ProgressBar1.Value := M4.Current_Frame;
            end);
        end;
      DisposeObject(mr);
      DisposeObject(M4);
      DoStatus('��Ƶ�����Ѿ���ʼ�����');

      TThread.Synchronize(ThSender, procedure
        begin
          TrackBar1.Max := imgList.Count;
          TrackBar1.Min := 0;
          TrackBar1.Value := 0;
          FillVideo := False;

          ProgressBar1.Visible := False;
        end);
    end);
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  DoStatus();
  cadencer_eng.Progress;
end;

procedure TForm1.PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
var
  d: TDrawEngine;
  tr: Double;
  trr: TRectV2;
begin
  drawIntf.SetSurface(Canvas, Sender);
  d := DrawPool(Sender, drawIntf);
  d.ViewOptions := [devpFPS];
  d.FPSFontColor := DEColor(0.5, 0.5, 1, 1);
  d.FillBox(d.ScreenRect, DEColor(0, 0, 0));

  LastDrawRect := d.FitDrawTexture(Frame, Frame.BoundsRectV2, d.ScreenRect, 1.0);
  d.DrawBox(LastDrawRect, DEColor(1, 0, 0, 0.5), 1);

  if mouse_down then
    begin
      d.DrawBox(RectV2(down_PT, move_PT), DEColor(0, 1, 0, 1), 1);
      d.DrawCorner(TV2Rect4.Init(RectV2(down_PT, move_PT), 0), DEColor(0, 1, 0, 1), 20, 5);
    end
  else if (not FillVideo) and (tracker_hnd <> nil) and (Tracker_CheckBox.IsChecked) then
    begin
      tr := ai.Tracker_Update(tracker_hnd, Frame, trr);
      trr := RectAdd(trr, LastDrawRect[0]);
      d.DrawBox(trr, DEColor(0.5, 0.5, 0.5), 5);
      d.DrawText(PFormat('%f', [tr]), 11, trr, DEColor(0.5, 0.5, 0.5), False);
    end;

  // ִ�л�ͼָ��
  d.Flush;
end;

procedure TForm1.CadencerProgress(const deltaTime, newTime: Double);
begin
  EnginePool.Progress(deltaTime);
  Invalidate;
end;

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
var
  i: Integer;
begin
  DisposeObject(Frame);
  EnginePool.Clear;

  DisposeObject(tmpFileStream);
  umlDeleteFile(tmpFileName);

  for i := 0 to imgList.Count - 1 do
      DisposeObject(imgList[i]);
  DisposeObject(imgList);

  ai.Tracker_Close(tracker_hnd);

  DisposeObject(drawIntf);
  DisposeObject(ai);
  DisposeObject(cadencer_eng);
  DisposeObject(VideoSeri);
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FillVideo;
end;

procedure TForm1.PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
Shift: TShiftState; X, Y: Single);
begin
  mouse_down := True;
  down_PT := Vec2(X, Y);
end;

procedure TForm1.PaintBox1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  move_PT := Vec2(X, Y);
end;

procedure TForm1.PaintBox1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  mouse_down := False;
  move_PT := Vec2(X, Y);

  if FillVideo then
      exit;

  ai.Tracker_Close(tracker_hnd);
  tracker_hnd := ai.Tracker_Open(Frame, ForwardRect(RectSub(RectV2(down_PT, move_PT), LastDrawRect[0])));
end;

procedure TForm1.TrackBar1Change(Sender: TObject);
var
  idx: Integer;
begin
  idx := Round(TrackBar1.Value);
  if (idx >= 0) and (idx < imgList.Count) then
    begin
      Frame.Assign(imgList[idx]);
      Frame.ReleaseFMXResource;
      imgList[idx].RecycleMemory;
    end;
end;

end.

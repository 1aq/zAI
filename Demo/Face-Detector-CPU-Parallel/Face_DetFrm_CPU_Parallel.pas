unit Face_DetFrm_CPU_Parallel;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo, FMX.Layouts, FMX.ExtCtrls,

  System.IOUtils,
  System.Threading,

  CoreClasses, zAI, zAI_Common, zDrawEngineInterface_SlowFMX, zDrawEngine, MemoryRaster, MemoryStream64,
  DoStatusIO,
  PascalStrings, UnicodeMixedLib, Geometry2DUnit, Geometry3DUnit;

type
  TFace_DetForm = class(TForm)
    Memo1: TMemo;
    PaintBox1: TPaintBox;
    AddPicButton: TButton;
    Timer1: TTimer;
    Scale2CheckBox: TCheckBox;
    OpenDialog: TOpenDialog;
    procedure AddPicButtonClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBox1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBox1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBox1MouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
    procedure PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
    procedure Timer1Timer(Sender: TObject);
  private
    lbc_Down: Boolean;
    lbc_pt: TVec2;
    procedure DoStatus_Hook_(AText: SystemString; const ID: Integer);
  public
    drawIntf: TDrawEngineInterface_FMX;
    rList: TMemoryRasterList;
    ai_Parallel: TAI_Parallel;
  end;

var
  Face_DetForm: TFace_DetForm;

implementation

{$R *.fmx}


procedure TFace_DetForm.AddPicButtonClick(Sender: TObject);
var
  i: Integer;
begin
  OpenDialog.Filter := TBitmapCodecManager.GetFilterString;
  if not OpenDialog.Execute then
      exit;

  for i := 0 to rList.Count - 1 do
      DisposeObject(rList[i]);
  rList.clear;

  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    begin
      TParallel.for(0, OpenDialog.Files.Count - 1, procedure(pass: Integer)
        var
          j: Integer;
          mr, nmr: TMemoryRaster;
          d: TDrawEngine;
          face_hnd: TFACE_Handle;
          r: TRectV2;
          ai: TAI;
        begin
          ai := ai_Parallel.GetAndLockAI;
          try
            mr := NewRasterFromFile(OpenDialog.Files[pass]);
            if Scale2CheckBox.IsChecked then
              begin
                nmr := NewRaster;
                nmr.ZoomFrom(mr, mr.width * 4, mr.height * 4);
                face_hnd := ai.Face_Detector_Rect(nmr);
                DisposeObject(nmr);
              end
            else
              begin
                face_hnd := ai.Face_Detector_Rect(mr);
              end;

            if face_hnd <> nil then
              for j := 0 to ai.Face_Rect_Num(face_hnd) - 1 do
                begin
                  d := TDrawEngine.Create;
                  d.Rasterization.SetWorkMemory(mr);
                  d.SetSize(mr);

                  r := ai.Face_RectV2(face_hnd, j);
                  if Scale2CheckBox.IsChecked then
                      r := RectMul(r, 0.25);
                  d.DrawCorner(TV2Rect4.Init(r, 0), DEColor(1, 0, 0, 0.9), 10, 4);
                  d.Flush;
                  DisposeObject(d);
                end;

            ai.Face_Close(face_hnd);

            LockObject(rList);
            rList.Add(mr);
            UnLockObject(rList);
          finally
              ai.Unlock;
          end;
        end);
    end);
end;

procedure TFace_DetForm.DoStatus_Hook_(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
  Memo1.GoToTextEnd;
end;

procedure TFace_DetForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  DeleteDoStatusHook(Self);
end;

procedure TFace_DetForm.FormCreate(Sender: TObject);
begin
  AddDoStatusHookM(Self, DoStatus_Hook_);
  // ��ȡzAI������
  ReadAIConfig;
  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();
  ai_Parallel := TAI_Parallel.Create;

  DoStatus('��ʼ�����нṹ.');
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    begin
      ai_Parallel.Prepare_Parallel(Prepare_AI_Engine, 4);
      DoStatus('���нṹ�������.');
    end);

  drawIntf := TDrawEngineInterface_FMX.Create;
  rList := TMemoryRasterList.Create;

  lbc_Down := False;
  lbc_pt := Vec2(0, 0);
end;

procedure TFace_DetForm.PaintBox1MouseDown(Sender: TObject; Button:
  TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  lbc_pt := Vec2(TControl(Sender).LocalToAbsolute(Pointf(X, Y)));
end;

procedure TFace_DetForm.PaintBox1MouseMove(Sender: TObject; Shift: TShiftState;
X, Y: Single);
var
  abs_pt, pt: TVec2;
  d: TDrawEngine;
begin
  abs_pt := Vec2(TControl(Sender).LocalToAbsolute(Pointf(X, Y)));
  pt := Vec2Sub(abs_pt, lbc_pt);
  d := DrawPool(Sender);

  if (ssLeft in Shift) then
      d.Offset := Vec2Add(d.Offset, pt);

  lbc_pt := Vec2(TControl(Sender).LocalToAbsolute(Pointf(X, Y)));
end;

procedure TFace_DetForm.PaintBox1MouseUp(Sender: TObject; Button: TMouseButton;
Shift: TShiftState; X, Y: Single);
begin
  lbc_Down := False;
end;

procedure TFace_DetForm.PaintBox1MouseWheel(Sender: TObject; Shift:
  TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  Handled := True;
  if WheelDelta > 0 then
    begin
      with DrawPool(PaintBox1) do
          Scale := Scale + 0.05;
    end
  else
    begin
      with DrawPool(PaintBox1) do
          Scale := Scale - 0.05;
    end;
end;

procedure TFace_DetForm.PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
var
  d: TDrawEngine;
begin
  // ��DrawIntf�Ļ�ͼʵ�������paintbox1
  drawIntf.SetSurface(Canvas, Sender);
  d := DrawPool(Sender, drawIntf);

  // ��ʾ�߿��֡��
  d.ViewOptions := [voEdge];

  // ���������ɺ�ɫ������Ļ�ͼָ���������ִ�еģ������γ����������д����DrawEngine��һ��������
  d.FillBox(d.ScreenRect, DEColor(0, 0, 0, 1));

  LockObject(rList);
  d.DrawPicturePackingInScene(rList, 5, Vec2(0, 0), 1.0);
  UnLockObject(rList);

  d.BeginCaptureShadow(Vec2(1, 1), 0.9);
  d.DrawText(d.LastDrawInfo + #13#10 + '�������任���꣬���ֿ�������', 12, d.ScreenRect, DEColor(0.5, 1, 0.5, 1), False);
  d.EndCaptureShadow;
  d.Flush;
end;

procedure TFace_DetForm.Timer1Timer(Sender: TObject);
begin
  EnginePool.Progress(Interval2Delta(Timer1.Interval));
  Invalidate;
  DoStatus;
end;

end.
